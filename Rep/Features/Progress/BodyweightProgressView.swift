import Charts
import SwiftData
import SwiftUI

struct BodyweightProgressView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BodyweightEntry.measuredAt, order: .reverse)
    private var entries: [BodyweightEntry]

    @Query private var settings: [UserSettings]

    @State private var timeRange: ProgressTimeRange = .sixMonths
    @State private var visibleEntries: [BodyweightEntry] = []
    @State private var entryBeingEdited: BodyweightEntry?
    @State private var isAddingEntry = false
    @State private var entryPendingDeletion: BodyweightEntry?
    @State private var errorMessage: String?

    private var preferredUnit: WeightUnit {
        settings.first?.preferredWeightUnit ?? .kilograms
    }

    private var latestEntry: BodyweightEntry? { visibleEntries.last }

    private var change: Double? {
        guard let first = visibleEntries.first, let last = visibleEntries.last, first.id != last.id else { return nil }
        return displayWeight(last.weightKilograms - first.weightKilograms)
    }

    private var entriesSignature: String {
        "\(entries.count)|\(timeRange.rawValue)|\(entries.first?.updatedAt.timeIntervalSinceReferenceDate ?? 0)"
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No bodyweight entries", systemImage: "scalemass")
                } description: {
                    Text("Log an entry to see how your bodyweight changes over time.")
                } actions: {
                    Button("Add bodyweight") { isAddingEntry = true }
                        .repPrimaryButton()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RepVisualSystem.pageSpacing) {
                        Picker("Time range", selection: $timeRange) {
                            ForEach(ProgressTimeRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)

                        if visibleEntries.isEmpty {
                            ContentUnavailableView(
                                "No entries in this range",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("Choose a longer time range to see earlier entries.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            bodyweightChart
                            summaryCards
                            entryList
                        }
                    }
                    .padding(.horizontal, RepVisualSystem.pageSpacing)
                    .padding(.bottom, RepVisualSystem.pageSpacing)
                }
                .scrollIndicators(.hidden)
                .repSoftScrollEdges()
            }
        }
        .task(id: entriesSignature) {
            visibleEntries = entries
                .filter { timeRange.includes($0.measuredAt) }
                .sorted { $0.measuredAt < $1.measuredAt }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add bodyweight", systemImage: "plus") {
                    isAddingEntry = true
                }
            }
        }
        .sheet(isPresented: $isAddingEntry) {
            BodyweightEntryEditor(entry: nil, preferredUnit: preferredUnit) { kilograms, date, notes in
                let entry = BodyweightEntry(
                    measuredAt: date,
                    weightKilograms: kilograms,
                    notes: notes,
                    source: .manual
                )
                modelContext.insert(entry)
                persist()
            }
        }
        .sheet(item: $entryBeingEdited) { entry in
            BodyweightEntryEditor(entry: entry, preferredUnit: preferredUnit) { kilograms, date, notes in
                entry.weightKilograms = kilograms
                entry.measuredAt = date
                entry.notes = notes
                entry.updatedAt = .now
                persist()
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entryPendingDeletion {
                    modelContext.delete(entryPendingDeletion)
                    persist()
                    self.entryPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
        }
        .alert("Couldn’t save the change", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var bodyweightChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bodyweight")
                        .font(.headline)
                    Text("Entries in the selected range")
                        .font(.caption)
                        .repSecondaryText()
                }

                Spacer()

                if let latestEntry {
                    Text(formattedWeight(latestEntry.weightKilograms))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(RepVisualSystem.tint)
                }
            }

            let yValues = visibleEntries.map { displayWeight($0.weightKilograms) }
            let yDomain = ProgressChartScale.niceYDomain(
                for: yValues,
                minimumPadding: preferredUnit == .kilograms ? 0.5 : 1
            )
            let yStride = yDomain.map { ProgressChartScale.axisStride(for: $0) } ?? 1
            let dayStride = ProgressChartScale.dayStride(for: visibleEntries.map(\.measuredAt))

            Chart(visibleEntries) { entry in
                LineMark(
                    x: .value("Date", entry.measuredAt, unit: .minute),
                    y: .value("Bodyweight", displayWeight(entry.weightKilograms))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)

                if visibleEntries.count <= 24 {
                    PointMark(
                        x: .value("Date", entry.measuredAt, unit: .minute),
                        y: .value("Bodyweight", displayWeight(entry.weightKilograms))
                    )
                    .symbolSize(24)
                    .foregroundStyle(.tint)
                }
            }
            .animation(.none, value: visibleEntries)
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
            .accessibilityLabel("Bodyweight history chart in \(preferredUnit.displayName.lowercased())")
        }
        .padding(16)
        .repSurface()
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            BodyweightMetricCard(
                title: "Latest",
                value: latestEntry.map { formattedWeight($0.weightKilograms) } ?? "—"
            )
            BodyweightMetricCard(
                title: "Change",
                value: change.map {
                    let prefix = $0 > 0 ? "+" : ""
                    return "\(prefix)\($0.formatted(.number.precision(.fractionLength(0...1)))) \(preferredUnit.symbol)"
                } ?? "—"
            )
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entries")
                .font(.headline)

            ForEach(visibleEntries.reversed()) { entry in
                Button {
                    entryBeingEdited = entry
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.measuredAt, format: .dateTime.month(.wide).day().year().hour().minute())
                                .foregroundStyle(.primary)
                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                                    .font(.caption)
                                    .repSecondaryText()
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(formattedWeight(entry.weightKilograms))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(formattedWeight(entry.weightKilograms)) on \(entry.measuredAt.formatted(date: .long, time: .omitted))")
                .accessibilityHint("Opens this entry for editing")
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        entryPendingDeletion = entry
                    }
                }

                if entry.id != visibleEntries.first?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .repSurface()
    }

    private func displayWeight(_ kilograms: Double) -> Double {
        UnitConversion.weight(kilograms, from: .kilograms, to: preferredUnit)
    }

    private func formattedWeight(_ kilograms: Double) -> String {
        UnitConversion.displayWeight(kilograms: kilograms, unit: preferredUnit)
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BodyweightMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: title == "Latest" ? "scalemass" : "arrow.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RepVisualSystem.tint)
                .frame(width: 30, height: 30)
                .background(RepVisualSystem.tint.opacity(0.1), in: .rect(cornerRadius: 9))
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .repSecondaryText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 106)
        .padding(14)
        .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        .accessibilityElement(children: .combine)
    }
}

private struct BodyweightEntryEditor: View {
    @Environment(\.dismiss) private var dismiss

    let entry: BodyweightEntry?
    let preferredUnit: WeightUnit
    let onSave: (Double, Date, String) -> Void

    @State private var displayedWeight: Double
    @State private var measuredAt: Date
    @State private var notes: String
    @State private var showValidationError = false

    init(
        entry: BodyweightEntry?,
        preferredUnit: WeightUnit,
        onSave: @escaping (Double, Date, String) -> Void
    ) {
        self.entry = entry
        self.preferredUnit = preferredUnit
        self.onSave = onSave

        let kilograms = entry?.weightKilograms ?? 0
        _displayedWeight = State(initialValue: UnitConversion.weight(kilograms, from: .kilograms, to: preferredUnit))
        _measuredAt = State(initialValue: entry?.measuredAt ?? .now)
        _notes = State(initialValue: entry?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", value: $displayedWeight, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                            .accessibilityLabel("Bodyweight in \(preferredUnit.displayName.lowercased())")
                        Text(preferredUnit.symbol)
                            .repSecondaryText()
                    }

                    DatePicker("Measured", selection: $measuredAt, in: ...Date())
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(entry == nil ? "Add bodyweight" : "Edit bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Enter a valid weight", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Weight must be greater than zero.")
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard displayedWeight > 0, displayedWeight.isFinite else {
            showValidationError = true
            return
        }
        let kilograms = UnitConversion.weight(displayedWeight, from: preferredUnit, to: .kilograms)
        onSave(kilograms, measuredAt, notes.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
