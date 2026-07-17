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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var settings: [UserSettings]

    @State private var selectedTab: AppTab = .today
    @State private var presentedWorkout: WorkoutSession?
    @State private var hasRestoredActiveWorkout = false
    @State private var isPreparingApp = true
    @State private var startupError: String?
    @State private var pageDragOffset: CGFloat = 0
    @State private var restTimerBridge = ActiveWorkoutRestTimerBridge.shared

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
                    .repTabPage(
                        .today,
                        selection: selectedTab,
                        width: geometry.size.width,
                        dragOffset: pageDragOffset
                    )

                    HistoryView(onOpenWorkout: present)
                        .repTabPage(
                            .history,
                            selection: selectedTab,
                            width: geometry.size.width,
                            dragOffset: pageDragOffset
                        )

                    TrainingProgressView()
                        .repTabPage(
                            .progress,
                            selection: selectedTab,
                            width: geometry.size.width,
                            dragOffset: pageDragOffset
                        )

                    RoutinesView(onStartRoutine: start)
                        .repTabPage(
                            .routines,
                            selection: selectedTab,
                            width: geometry.size.width,
                            dragOffset: pageDragOffset
                        )

                    SettingsView()
                        .repTabPage(
                            .settings,
                            selection: selectedTab,
                            width: geometry.size.width,
                            dragOffset: pageDragOffset
                        )
                }
                .simultaneousGesture(mainScreenPager(width: geometry.size.width))
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if let restTimer = restTimerBridge.presentedTimer, restTimer.isPresented {
                    WorkoutRestTimerBanner(restTimer: restTimer)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                RepTransparentTabBar(
                    selection: selectedTab,
                    hasActiveWorkout: presentedWorkout != nil,
                    onSelect: selectTab
                )
            }
            .animation(.snappy(duration: 0.25), value: restTimerBridge.presentedTimer?.isPresented ?? false)
            .allowsHitTesting(true)

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
            async let minimumSplash: Void = {
                try? await Task.sleep(for: .milliseconds(900))
            }()
            HapticEngineManager.shared.warm()
            RestTimerLiveActivityManager.reconcileOnLaunch()
            await bootstrapLocalStore()
            generateDevelopmentSampleDataIfRequested()
            restoreActiveWorkoutIfNeeded()
            warmExercisePickerCache()
            prewarmMainScreenData()
            _ = await minimumSplash
            withAnimation(.easeOut(duration: 0.35)) {
                isPreparingApp = false
            }
#if DEBUG
            startDevelopmentRestTimerIfRequested()
#endif
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
        withTransaction(Transaction(animation: nil)) {
            pageDragOffset = 0
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

#if DEBUG
    private func startDevelopmentRestTimerIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-RepStartRestTimer") else { return }
        Task { @MainActor in
            // Wait for ActivityKit + scene to be ready after cold launch.
            try? await Task.sleep(for: .milliseconds(800))
            let haptics = (try? modelContext.fetch(FetchDescriptor<UserSettings>()).first?.hapticsEnabled) ?? true
            RestTimerDevTools.startScreenshotTimer(hapticsEnabled: haptics)
        }
    }
#endif

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

    private func mainScreenPager(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard presentedWorkout == nil else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.15 else { return }

                let selectedIndex = selectedTab.rawValue
                let lastIndex = AppTab.allCases.count - 1
                let isPullingPastFirst = selectedIndex == 0 && horizontal > 0
                let isPullingPastLast = selectedIndex == lastIndex && horizontal < 0
                let resistance = isPullingPastFirst || isPullingPastLast ? 0.18 : 1

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    pageDragOffset = horizontal * resistance
                }
            }
            .onEnded { value in
                guard presentedWorkout == nil else {
                    pageDragOffset = 0
                    return
                }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let projectedHorizontal = value.predictedEndTranslation.width
                let tabs = AppTab.allCases
                guard let index = tabs.firstIndex(of: selectedTab),
                      abs(horizontal) > abs(vertical) * 1.15 else {
                    settlePage(on: selectedTab)
                    return
                }

                let shouldAdvance = abs(horizontal) > width * 0.24
                    || abs(projectedHorizontal) > width * 0.48
                let direction = abs(projectedHorizontal) > abs(horizontal)
                    ? projectedHorizontal
                    : horizontal
                var destination = selectedTab
                if shouldAdvance, direction < 0,
                   index < tabs.index(before: tabs.endIndex) {
                    destination = tabs[index + 1]
                } else if shouldAdvance, direction > 0,
                          index > tabs.startIndex {
                    destination = tabs[index - 1]
                }
                settlePage(on: destination)
            }
    }

    private func settlePage(on destination: AppTab) {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
            selectedTab = destination
            pageDragOffset = 0
        }
    }
}

private extension View {
    func repTabPage(
        _ tab: AppTab,
        selection: AppTab,
        width: CGFloat,
        dragOffset: CGFloat
    ) -> some View {
        // Clear inset so UIKit-backed List/Form content can scroll above the overlay tab bar.
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: RepVisualSystem.mainTabBarReservedHeight)
        }
        .offset(x: CGFloat(tab.rawValue - selection.rawValue) * width + dragOffset)
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
    @State private var isBreathing = false
    @State private var ringSpin = false
    @State private var loaderPulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.11, blue: 0.36),
                    Color(red: 0.05, green: 0.38, blue: 0.90),
                    Color(red: 0.11, green: 0.55, blue: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.25, green: 0.90, blue: 1.0).opacity(0.30))
                .frame(width: 340, height: 340)
                .blur(radius: 72)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color(red: 1.0, green: 0.48, blue: 0.20).opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 64)
                .offset(x: 140, y: 280)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.05),
                                    .white.opacity(0.45),
                                    Color(red: 0.2, green: 0.85, blue: 0.85).opacity(0.55),
                                    .white.opacity(0.05)
                                ],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 148, height: 148)
                        .rotationEffect(.degrees(ringSpin ? 360 : 0))

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.18),
                                    .white.opacity(0.03),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 12,
                                endRadius: 80
                            )
                        )
                        .frame(width: 158, height: 158)

                    RepMascot(pose: .welcome, size: 118)
                        .scaleEffect(isBreathing ? 1.03 : 0.99)
                        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
                }

                VStack(spacing: 8) {
                    Text("REP")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .tracking(7)
                        .foregroundStyle(.white)

                    Text("Ready for your next set")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 7, height: 7)
                            .scaleEffect(loaderPulse ? 1 : 0.55)
                            .opacity(loaderPulse ? 1 : 0.35)
                            .animation(
                                .easeInOut(duration: 0.55)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.14),
                                value: loaderPulse
                            )
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rep is getting ready")
        .task {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            withAnimation(.linear(duration: 4.8).repeatForever(autoreverses: false)) {
                ringSpin = true
            }
            loaderPulse = true
        }
    }
}
