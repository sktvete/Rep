import SwiftData
import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var routine: Routine

    @State private var isChoosingExercise = false
    @State private var itemBeingConfigured: RoutineExercise?
    @State private var exercisePendingRemoval: RoutineExercise?
    @State private var exerciseOrderIDs: [UUID]
    @State private var routinePendingDeletion = false
    @State private var operationError: String?
    @State private var debouncedSaveTask: Task<Void, Never>?

    private let onStartRoutine: () -> Void

    init(routine: Routine, onStartRoutine: @escaping () -> Void = {}) {
        self.routine = routine
        self.onStartRoutine = onStartRoutine
        _exerciseOrderIDs = State(
            initialValue: routine.exercises.sorted { $0.orderIndex < $1.orderIndex }.map(\.id)
        )
    }

    private var persistedOrderedExercises: [RoutineExercise] {
        routine.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var orderedExercises: [RoutineExercise] {
        let byID = Dictionary(uniqueKeysWithValues: routine.exercises.map { ($0.id, $0) })
        let arranged = exerciseOrderIDs.compactMap { byID[$0] }
        let arrangedIDs = Set(arranged.map(\.id))
        return arranged + persistedOrderedExercises.filter { !arrangedIDs.contains($0.id) }
    }

    private var reorderExerciseBinding: Binding<[RoutineExercise]> {
        Binding(
            get: { orderedExercises },
            set: { exerciseOrderIDs = $0.map(\.id) }
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.caption.weight(.semibold))
                            .repSecondaryText()
                        TextField("Routine name", text: $routine.name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onSubmit(keepChanges)
                            .onChange(of: routine.name) { _, _ in scheduleKeepChanges() }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .repSecondaryText()
                        TextField("Optional", text: $routine.notes, axis: .vertical)
                            .lineLimit(1...3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: routine.notes) { _, _ in scheduleKeepChanges() }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.caption.weight(.semibold))
                            .repSecondaryText()
                        RoutineColorPicker(selection: Binding(
                            get: { routine.colorPreset },
                            set: { preset in
                                routine.colorPreset = preset
                                scheduleKeepChanges()
                            }
                        ))
                    }
                }
                .repThemedListSection(padding: 16)
            } header: {
                RepSectionHeader(title: "Routine")
            }

            Section {
                if !orderedExercises.isEmpty {
                    RepLiveReorderStack(
                        items: reorderExerciseBinding,
                        id: \.id,
                        axis: .vertical,
                        spacing: 8,
                        onInteraction: { ExerciseThumbnailIdlePreloader.shared.cancel() },
                        onStationaryHold: { exerciseID in
                            exercisePendingRemoval = orderedExercises.first { $0.id == exerciseID }
                        },
                        onCommit: commitExerciseOrder
                    ) { item, _ in
                        let index = orderedExercises.firstIndex { $0.id == item.id }
                        Button {
                            itemBeingConfigured = item
                        } label: {
                            HStack(spacing: 10) {
                                RoutineExerciseRow(item: item, listIndex: index)
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .repSurface(cornerRadius: 14, shadowRadius: 3, shadowY: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Tap for set and rest settings. Hold and move to reorder; keep holding to remove")
                        .accessibilityAction(named: "Remove exercise") {
                            exercisePendingRemoval = item
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(RepThemedList.rowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Button {
                    isChoosingExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(routine.colorPreset.color)
                .repThemedListRow()
            } header: {
                RepSectionHeader(title: "Exercises")
            } footer: {
                Text(
                    orderedExercises.isEmpty
                        ? "Add the movements for this routine. You can tune sets and rest on each exercise."
                        : "Hold an exercise, then move it to reorder. Keep holding to remove it."
                )
            }

            Section {
                Button("Delete Routine", systemImage: "trash", role: .destructive) {
                    routinePendingDeletion = true
                }
                .repThemedListRow()
            }
        }
        .repThemedList()
        .scrollClipDisabled()
        // Start bar + tab-bar spacer already reserve the bottom via safeAreaInset.
        .contentMargins(.bottom, 8, for: .scrollContent)
        .background(RepScreenBackground())
        .exerciseThumbnailScope {
            ExerciseThumbnailPrefetch.sources(
                from: orderedExercises.compactMap(\.exercise),
                thumbnailSize: 36
            )
        }
        .navigationTitle(routine.name.isEmpty ? "Routine" : routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(routine.colorPreset.color)
        .onAppear {
            ExerciseThumbnailIdlePreloader.shared.cancel()
            reconcileExerciseOrder()
        }
        .onChange(of: routine.exercises.map(\.id)) { _, _ in
            reconcileExerciseOrder()
        }
        .onDisappear {
            debouncedSaveTask?.cancel()
            keepChanges()
            ExercisePickerSessionCache.scheduleIdleThumbnailPrefetch()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !routine.isArchived {
                VStack(spacing: 0) {
                    Button(action: onStartRoutine) {
                        Text("Start \(routine.name.isEmpty ? "Workout" : routine.name)")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .repPrimaryButton()
                    .tint(routine.colorPreset.color)
                    .controlSize(.large)
                    .disabled(orderedExercises.isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)

                    // Lift above the floating root tab bar (overlay, not a system inset).
                    Color.clear.frame(height: RepVisualSystem.mainTabBarReservedHeight)
                }
            }
        }
        .sheet(isPresented: $isChoosingExercise) {
            ExercisePickerView { exercise in
                add(exercise)
                isChoosingExercise = false
            }
        }
        .sheet(item: $itemBeingConfigured) { item in
            RoutineExerciseConfigurationView(item: item, onPersist: keepChanges)
        }
        .confirmationDialog(
            "Remove this exercise?",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive) {
                if let exercisePendingRemoval {
                    removeExercise(exercisePendingRemoval)
                }
                exercisePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { exercisePendingRemoval = nil }
        }
        .alert("Delete routine?", isPresented: $routinePendingDeletion) {
            Button("Delete", role: .destructive) {
                modelContext.delete(routine)
                do {
                    try modelContext.save()
                    dismiss()
                } catch {
                    operationError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past workouts will not be changed.")
        }
        .alert("Couldn’t save changes", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationError ?? "Please try again.")
        }
    }

    private func add(_ exercise: Exercise) {
        let item = RoutineExercise(
            exercise: exercise,
            orderIndex: orderedExercises.count,
            targetSetCount: 3,
            suggestedRepetitions: 8,
            defaultRestSeconds: 90
        )
        routine.appendExercise(item)
        exerciseOrderIDs.append(item.id)
        keepChanges()
    }

    private func removeExercise(_ item: RoutineExercise) {
        var items = orderedExercises
        items.removeAll { $0.id == item.id }
        routine.exercises.removeAll { $0.id == item.id }
        exerciseOrderIDs.removeAll { $0 == item.id }
        modelContext.delete(item)
        updateOrder(of: items)
    }

    private func commitExerciseOrder(_ items: [RoutineExercise]) {
        guard items.map(\.id) != persistedOrderedExercises.map(\.id) else { return }
        updateOrder(of: items)
    }

    private func updateOrder(of items: [RoutineExercise]) {
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
        exerciseOrderIDs = items.map(\.id)
        routine.updatedAt = .now
        keepChanges()
    }

    private func reconcileExerciseOrder() {
        let modelIDs = Set(routine.exercises.map(\.id))
        let retained = exerciseOrderIDs.filter { modelIDs.contains($0) }
        let retainedIDs = Set(retained)
        exerciseOrderIDs = retained + persistedOrderedExercises.map(\.id).filter {
            !retainedIDs.contains($0)
        }
    }

    private func scheduleKeepChanges() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            keepChanges()
        }
    }

    private func keepChanges() {
        routine.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct RoutineExerciseRow: View {
    let item: RoutineExercise
    var listIndex: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let exercise = item.exercise {
                ExerciseMediaThumbnail(exercise: exercise, size: 36, listIndex: listIndex)
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.1), in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.exercise?.name ?? "Unavailable Exercise")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(item.targetSetCount) sets · \(item.suggestedRepetitions) reps · \(restDescription)")
                    .font(.caption)
                    .repSecondaryText()
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var restDescription: String {
        if item.defaultRestSeconds >= 60, item.defaultRestSeconds.isMultiple(of: 60) {
            return "\(item.defaultRestSeconds / 60) min rest"
        }
        return "\(item.defaultRestSeconds) sec rest"
    }
}

private struct RoutineExerciseConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: RoutineExercise
    let onPersist: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 0) {
                        Stepper(value: $item.targetSetCount, in: 1...20) {
                            LabeledContent("Target Sets", value: "\(item.targetSetCount)")
                        }
                        .accessibilityValue("\(item.targetSetCount) sets")

                        Divider().padding(.vertical, 12)

                        Stepper(value: $item.suggestedRepetitions, in: 1...100) {
                            LabeledContent("Repetitions", value: "\(item.suggestedRepetitions)")
                        }
                        .accessibilityValue("\(item.suggestedRepetitions) repetitions")
                    }
                    .repThemedListSection()
                } header: {
                    RepSectionHeader(title: item.exercise?.name ?? "Exercise")
                }

                Section {
                    Stepper(value: $item.defaultRestSeconds, in: 0...900, step: 15) {
                        LabeledContent("After each set", value: duration(item.defaultRestSeconds))
                    }
                    .repThemedListSection()
                } header: {
                    RepSectionHeader(title: "Rest")
                }

                Section {
                    TextField("Setup, tempo, or reminder", text: $item.notes, axis: .vertical)
                        .lineLimit(2...5)
                        .repThemedListSection()
                } header: {
                    RepSectionHeader(title: "Notes")
                }
            }
            .repThemedList()
            .contentMargins(.bottom, RepVisualSystem.pageSpacing, for: .scrollContent)
            .background(RepScreenBackground())
            .navigationTitle("Exercise Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onPersist()
                        dismiss()
                    }
                }
            }
            .onDisappear(perform: onPersist)
        }
    }

    private func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

#Preview {
    let routine = Routine(name: "Push")
    return NavigationStack {
        RoutineEditorView(routine: routine)
    }
    .modelContainer(for: [Routine.self, RoutineExercise.self, Exercise.self], inMemory: true)
}
