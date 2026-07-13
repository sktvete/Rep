import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedSettings: [UserSettings]

    @State private var sampleDataAction: SampleDataAction?
    @State private var operationMessage: String?
    @State private var operationError: String?

    private var settings: UserSettings? { storedSettings.first }

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    SettingsForm(
                        settings: settings,
                        onGenerateSampleData: { sampleDataAction = .generate },
                        onClearSampleData: { sampleDataAction = .clear }
                    )
                } else {
                    ZStack {
                        RepScreenBackground()
                        ProgressView("Preparing settings…")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear(perform: createSettingsIfNeeded)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                sampleDataAction?.title ?? "Sample Data",
                isPresented: Binding(
                    get: { sampleDataAction != nil },
                    set: { if !$0 { sampleDataAction = nil } }
                ),
                titleVisibility: .visible,
                presenting: sampleDataAction
            ) { action in
                Button(action.buttonTitle, role: action.role) {
                    perform(action)
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(action.message)
            }
            .alert("Sample Data", isPresented: Binding(
                get: { operationMessage != nil },
                set: { if !$0 { operationMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationMessage ?? "Done.")
            }
            .alert("Couldn’t update sample data", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationError ?? "Please try again.")
            }
        }
    }

    private func createSettingsIfNeeded() {
        guard storedSettings.isEmpty else { return }
        modelContext.insert(UserSettings())
        do {
            try modelContext.save()
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func perform(_ action: SampleDataAction) {
        sampleDataAction = nil
        do {
            let service = DevelopmentSampleDataService(context: modelContext)
            switch action {
            case .generate:
                try service.generate(referenceDate: .now)
                settings?.hasGeneratedSampleData = true
                operationMessage = "Sample routines and workouts are ready."
            case .clear:
                try service.clear()
                settings?.hasGeneratedSampleData = false
                operationMessage = "Sample history has been removed."
            }
            settings?.updatedAt = .now
            try modelContext.save()
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct SettingsForm: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: UserSettings

    let onGenerateSampleData: () -> Void
    let onClearSampleData: () -> Void

    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Training") {
                Picker(selection: $settings.preferredWeightUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                } label: {
                    Label("Weight Unit", systemImage: "scalemass")
                }

                Stepper(value: $settings.defaultRestSeconds, in: 0...900, step: 15) {
                    LabeledContent {
                        Text(restDescription)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } label: {
                        Label("Default Rest", systemImage: "timer")
                    }
                }
                .accessibilityValue(restDescription)
            }

            Section {
                Toggle(isOn: $settings.hapticsEnabled) {
                    Label("Set Completion Haptics", systemImage: "waveform")
                }
                Toggle(isOn: $settings.patternSuggestionsEnabled) {
                    Label("Pattern Suggestions", systemImage: "sparkles")
                }
            } footer: {
                Text("Suggestions reflect routines you often choose. They never change a routine or start a workout on their own.")
            }

#if DEBUG
            Section {
                if settings.hasGeneratedSampleData {
                    Button("Remove Sample Data", systemImage: "trash", role: .destructive) {
                        onClearSampleData()
                    }
                } else {
                    Button("Generate Sample Data", systemImage: "sparkles") {
                        onGenerateSampleData()
                    }
                }

                Button("Test Rest Timer Haptics", systemImage: "waveform.path") {
                    Task { @MainActor in
                        await HapticFeedback.tripleBuzzAndWait()
                    }
                }

                Button("Start 5 Second Rest Timer", systemImage: "timer") {
                    RestTimerDevTools.startFiveSecondTimer(hapticsEnabled: settings.hapticsEnabled)
                }
            } header: {
                Text("Development")
            } footer: {
                Text("Adds local routines, workout history, bodyweight entries, and an active recovery example. Rest timer tests use the active workout when one is open, otherwise the Dynamic Island only.")
            }
#endif

            Section("Coming Later") {
                FutureIntegrationRow(
                    title: "iCloud Sync",
                    detail: "Not enabled",
                    systemImage: "icloud"
                )
                FutureIntegrationRow(
                    title: "Apple Health",
                    detail: "Not connected",
                    systemImage: "heart"
                )
                FutureIntegrationRow(
                    title: "Export Workouts",
                    detail: "Not available",
                    systemImage: "square.and.arrow.up"
                )
                FutureIntegrationRow(
                    title: "Apple Watch",
                    detail: "Not available",
                    systemImage: "applewatch"
                )
            }

            Section("About") {
                LabeledContent {
                    Text("On this device")
                } label: {
                    Label("Storage", systemImage: "iphone")
                }
                LabeledContent {
                    Text("Rep")
                } label: {
                    Label("App", systemImage: "info.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(RepScreenBackground())
        .onChange(of: settings.preferredWeightUnit) { _, _ in persist() }
        .onChange(of: settings.defaultRestSeconds) { _, _ in persist() }
        .onChange(of: settings.hapticsEnabled) { _, _ in persist() }
        .onChange(of: settings.patternSuggestionsEnabled) { _, _ in persist() }
        .alert("Couldn’t save settings", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private var restDescription: String {
        Duration.seconds(settings.defaultRestSeconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    private func persist() {
        settings.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct FutureIntegrationRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(.tint)
                .background(.tint.opacity(0.1), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum SampleDataAction: Hashable, Identifiable {
    case generate
    case clear

    var id: Self { self }

    var title: String {
        switch self {
        case .generate: "Generate sample data?"
        case .clear: "Remove sample data?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .generate: "Generate"
        case .clear: "Remove"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .generate: nil
        case .clear: .destructive
        }
    }

    var message: String {
        switch self {
        case .generate:
            "This adds local development history. It can be removed again from Settings."
        case .clear:
            "This removes generated sample history. Your own workouts are left in place."
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(
            for: [
                UserSettings.self,
                Exercise.self,
                Routine.self,
                RoutineExercise.self,
                WorkoutSession.self,
                WorkoutExercise.self,
                WorkoutSet.self,
                BodyweightEntry.self,
                LearnedPattern.self
            ],
            inMemory: true
        )
}
