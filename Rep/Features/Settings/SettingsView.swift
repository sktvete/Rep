import SwiftData
import SwiftUI
import UIKit

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
                        ProgressView("Loading settings…")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { ensureSettingsExist() }
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

    private func ensureSettingsExist() {
        if let existing = storedSettings.first {
            UserSettingsThemeMigration.backfill(existing)
            try? modelContext.save()
            return
        }

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
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var settings: UserSettings

    let onGenerateSampleData: () -> Void
    let onClearSampleData: () -> Void

    @State private var saveError: String?
    @State private var persistTask: Task<Void, Never>?
    @State private var draftTheme = RepThemeSettings()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Appearance", selection: appearancePreferenceBinding) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("\(appearanceName) color groups", systemImage: appearanceIcon)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Reset") {
                                draftTheme.reset(colorScheme)
                            }
                            .font(.subheadline)
                        }

                        RGBAColorGroupEditor(
                            title: "Accent",
                            detail: "Buttons, links, and selection",
                            systemImage: "paintbrush.fill",
                            color: paletteColorBinding(\.accent)
                        )
                        RGBAColorGroupEditor(
                            title: "Background",
                            detail: "App canvas",
                            systemImage: "rectangle.fill",
                            color: paletteColorBinding(\.background)
                        )
                        RGBAColorGroupEditor(
                            title: "Backdrop",
                            detail: "Card and list-row fill",
                            systemImage: "square.on.square.fill",
                            color: paletteColorBinding(\.surface)
                        )
                        RGBAColorGroupEditor(
                            title: "Backdrop Shadow",
                            detail: "Shadow behind cards and list rows",
                            systemImage: "square.stack.3d.down.right.fill",
                            color: paletteColorBinding(\.backdropShadow)
                        )
                        RGBAColorGroupEditor(
                            title: "Controls",
                            detail: "Secondary controls",
                            systemImage: "switch.2",
                            color: paletteColorBinding(\.controls)
                        )
                        RGBAColorGroupEditor(
                            title: "Secondary Text",
                            detail: "Grey captions and supporting text",
                            systemImage: "textformat",
                            color: paletteColorBinding(\.secondaryText)
                        )

                        ColorCodeSummary(palette: draftTheme.palette(for: colorScheme))

                        Text("Use the color well or fine-tune hue, saturation, value, and alpha with the sliders. Light and dark values are stored separately.")
                            .font(.caption)
                            .repSecondaryText()
                    }
                }
                .repThemedListSection()
            } header: {
                RepSectionHeader(title: "Appearance")
            }

            Section {
                VStack(spacing: 0) {
                    Picker(selection: $settings.preferredWeightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    } label: {
                        Label("Weight Unit", systemImage: "scalemass")
                    }

                    Divider().padding(.vertical, 12)

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
                .repThemedListSection()
            } header: {
                RepSectionHeader(title: "Training")
            }

            Section {
                VStack(spacing: 0) {
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label("Set Completion Haptics", systemImage: "waveform")
                    }

                    Divider().padding(.vertical, 12)

                    Toggle(isOn: $settings.patternSuggestionsEnabled) {
                        Label("Pattern Suggestions", systemImage: "sparkles")
                    }
                }
                .repThemedListSection()
            } footer: {
                Text("Suggestions reflect routines you often choose. They never change a routine or start a workout on their own.")
            }

#if DEBUG
            Section {
                VStack(spacing: 0) {
                    if settings.hasGeneratedSampleData {
                        Button("Remove Sample Data", systemImage: "trash", role: .destructive) {
                            onClearSampleData()
                        }
                    } else {
                        Button("Generate Sample Data", systemImage: "sparkles") {
                            onGenerateSampleData()
                        }
                    }

                    Divider().padding(.vertical, 12)

                    Button("Test Rest Timer Haptics", systemImage: "waveform.path") {
                        Task { @MainActor in
                            await HapticFeedback.tripleBuzzAndWait()
                        }
                    }

                    Divider().padding(.vertical, 12)

                    Button("Start 5 Second Rest Timer", systemImage: "timer") {
                        RestTimerDevTools.startFiveSecondTimer(hapticsEnabled: settings.hapticsEnabled)
                    }
                }
                .repThemedListSection()
            } header: {
                RepSectionHeader(title: "Development")
            } footer: {
                Text("Adds local routines, workout history, bodyweight entries, and an active recovery example. Rest timer tests use the active workout when one is open, otherwise the Dynamic Island only.")
            }
#endif

            Section {
                VStack(spacing: 0) {
                    FutureIntegrationRow(
                        title: "iCloud Sync",
                        detail: "Not enabled",
                        systemImage: "icloud"
                    )

                    Divider().padding(.vertical, 12)

                    FutureIntegrationRow(
                        title: "Apple Health",
                        detail: "Not connected",
                        systemImage: "heart"
                    )

                    Divider().padding(.vertical, 12)

                    FutureIntegrationRow(
                        title: "Export Workouts",
                        detail: "Not available",
                        systemImage: "square.and.arrow.up"
                    )

                    Divider().padding(.vertical, 12)

                    FutureIntegrationRow(
                        title: "Apple Watch",
                        detail: "Not available",
                        systemImage: "applewatch"
                    )
                }
                .repThemedListSection()
            } header: {
                RepSectionHeader(title: "Coming Later")
            }

            Section {
                VStack(spacing: 0) {
                    LabeledContent {
                        Text("On this device")
                    } label: {
                        Label("Storage", systemImage: "iphone")
                    }

                    Divider().padding(.vertical, 12)

                    LabeledContent {
                        Text("Rep")
                    } label: {
                        Label("App", systemImage: "info.circle")
                    }
                }
                .repThemedListSection()
            } header: {
                RepSectionHeader(title: "About")
            }
        }
        .repThemedList()
        .background(RepScreenBackground())
        .environment(\.repThemeSettings, draftTheme)
        .onAppear {
            draftTheme = RepThemeSettings(settings: settings)
        }
        .onChange(of: draftTheme) { _, newValue in
            newValue.apply(to: settings)
            schedulePersist()
        }
        .onChange(of: settings.appearancePreferenceRaw) { _, _ in schedulePersist() }
        .onChange(of: settings.preferredWeightUnit) { _, _ in schedulePersist() }
        .onChange(of: settings.defaultRestSeconds) { _, _ in schedulePersist() }
        .onChange(of: settings.hapticsEnabled) { _, _ in schedulePersist() }
        .onChange(of: settings.patternSuggestionsEnabled) { _, _ in schedulePersist() }
        .onDisappear {
            persistTask?.cancel()
            persist()
        }
        .alert("Couldn’t save settings", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private var appearancePreferenceBinding: Binding<AppAppearance> {
        Binding(
            get: { settings.appearancePreference },
            set: { settings.appearancePreference = $0 }
        )
    }

    private func paletteColorBinding(
        _ keyPath: WritableKeyPath<RepThemePalette, RepRGBAColor>
    ) -> Binding<RepRGBAColor> {
        Binding(
            get: { draftTheme.palette(for: colorScheme)[keyPath: keyPath] },
            set: { newColor in
                var palette = draftTheme.palette(for: colorScheme)
                palette[keyPath: keyPath] = newColor
                draftTheme.setPalette(palette, for: colorScheme)
            }
        )
    }

    private var appearanceName: String {
        colorScheme == .dark ? "Dark" : "Light"
    }

    private var appearanceIcon: String {
        colorScheme == .dark ? "moon.stars" : "sun.max"
    }

    private var restDescription: String {
        Duration.seconds(settings.defaultRestSeconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            persist()
        }
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

private struct RGBAColorGroupEditor: View {
    let title: String
    let detail: String
    let systemImage: String
    @Binding var color: RepRGBAColor

    @State private var isExpanded = false
    @State private var hsv: RepHSVColor

    init(
        title: String,
        detail: String,
        systemImage: String,
        color: Binding<RepRGBAColor>
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self._color = color
        self._hsv = State(initialValue: RepHSVColor(rgba: color.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: systemImage)
                            .frame(width: 22)
                            .repSecondaryText()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.subheadline.weight(.medium))
                            Text(detail)
                                .font(.caption2)
                                .repSecondaryText()
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                ColorPicker(
                    "\(title) color",
                    selection: Binding(
                        get: { color.color },
                        set: {
                            let updatedColor = RepRGBAColor(color: $0)
                            color = updatedColor
                            hsv = RepHSVColor(rgba: updatedColor)
                        }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
            }

            if isExpanded {
                VStack(spacing: 12) {
                    HSVChannelSlider(
                        label: "Hue",
                        valueText: "\(Int((hsv.hue * 360).rounded()))°",
                        value: hsvBinding(\.hue),
                        tint: Color(hue: hsv.hue, saturation: 0.85, brightness: 0.95)
                    )
                    HSVChannelSlider(
                        label: "Saturation",
                        valueText: "\(Int((hsv.saturation * 100).rounded()))%",
                        value: hsvBinding(\.saturation),
                        tint: color.color
                    )
                    HSVChannelSlider(
                        label: "Value",
                        valueText: "\(Int((hsv.value * 100).rounded()))%",
                        value: hsvBinding(\.value),
                        tint: color.color
                    )
                    HSVChannelSlider(
                        label: "Alpha",
                        valueText: "\(Int((hsv.alpha * 100).rounded()))%",
                        value: hsvBinding(\.alpha),
                        tint: color.color
                    )
                }

                Text("HSV \(Int((hsv.hue * 360).rounded()))°, \(Int((hsv.saturation * 100).rounded()))%, \(Int((hsv.value * 100).rounded()))%  •  \(color.rgbaDescription)")
                    .font(.caption.monospaced())
                    .repSecondaryText()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 13))
        .accessibilityElement(children: .contain)
        .onChange(of: color) { _, newColor in
            if newColor != hsv.rgba {
                hsv = RepHSVColor(rgba: newColor)
            }
        }
    }

    private func hsvBinding(_ keyPath: WritableKeyPath<RepHSVColor, Double>) -> Binding<Double> {
        Binding(
            get: { hsv[keyPath: keyPath] },
            set: { newValue in
                hsv[keyPath: keyPath] = min(max(newValue, 0), 1)
                color = hsv.rgba
            }
        )
    }
}

private struct HSVChannelSlider: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .repSecondaryText()
            }
            Slider(value: $value, in: 0...1)
                .tint(tint)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
        }
    }
}

private struct ColorCodeSummary: View {
    let palette: RepThemePalette

    @State private var copied = false

    private var entries: [(label: String, color: RepRGBAColor)] {
        [
            ("Accent", palette.accent),
            ("Background", palette.background),
            ("Backdrop", palette.surface),
            ("Shadow", palette.backdropShadow),
            ("Controls", palette.controls),
            ("Grey text", palette.secondaryText)
        ]
    }

    private var copyText: String {
        entries
            .map { "\($0.label): \($0.color.hexaDescription)" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current HEXA")
                    .font(.caption.weight(.semibold))
                    .repSecondaryText()
                Spacer()
                Button {
                    UIPasteboard.general.string = copyText
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(entries, id: \.label) { entry in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(entry.color.color)
                            .frame(width: 8, height: 8)
                        Text(entry.label)
                            .font(.caption2)
                            .repSecondaryText()
                        Spacer(minLength: 2)
                        Text(entry.color.hexaDescription)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 11))
        .accessibilityElement(children: .contain)
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
