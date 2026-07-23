import SwiftData
import SwiftUI

struct CreateRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notes = ""
    @State private var colorPreset: RoutineColorPreset = .blue
    @State private var selectedExercises: [Exercise] = []
    @State private var exercisePendingRemoval: Exercise?
    @State private var isChoosingExercise = false
    @State private var saveError: String?
    @FocusState private var isNameFocused: Bool

    private let embeddedInNavigationStack: Bool
    private let onDismiss: (() -> Void)?

    init(
        embeddedInNavigationStack: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        self.embeddedInNavigationStack = embeddedInNavigationStack
        self.onDismiss = onDismiss
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty
    }

    @ViewBuilder
    var body: some View {
        if embeddedInNavigationStack {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.caption.weight(.semibold))
                                .repSecondaryText()
                            TextField("Push, Pull, Legs…", text: $name)
                                .font(.title3.weight(.semibold))
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .focused($isNameFocused)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.caption.weight(.semibold))
                                .repSecondaryText()
                            TextField("Optional", text: $notes, axis: .vertical)
                                .lineLimit(1...3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color")
                                .font(.caption.weight(.semibold))
                                .repSecondaryText()
                            RoutineColorPicker(selection: $colorPreset)
                        }
                    }
                    .repThemedListSection(padding: 16)
                } header: {
                    RepSectionHeader(title: "Routine")
                }

                Section {
                    if !selectedExercises.isEmpty {
                        RepLiveReorderStack(
                            items: $selectedExercises,
                            id: \.id,
                            axis: .vertical,
                            spacing: 8,
                            onInteraction: { ExerciseThumbnailIdlePreloader.shared.cancel() },
                            onStationaryHold: { exerciseID in
                                exercisePendingRemoval = selectedExercises.first { $0.id == exerciseID }
                            }
                        ) { exercise, _ in
                            let index = selectedExercises.firstIndex { $0.id == exercise.id }
                            HStack(spacing: 12) {
                                ExerciseMediaThumbnail(exercise: exercise, size: 34, listIndex: index)
                                Text(exercise.name)
                                    .fontWeight(.medium)
                                Spacer(minLength: 8)
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .repSurface(cornerRadius: 14, shadowRadius: 3, shadowY: 1)
                            .accessibilityHint("Hold and move to reorder; keep holding to remove")
                            .accessibilityAction(named: "Remove exercise") {
                                exercisePendingRemoval = exercise
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
                    .foregroundStyle(colorPreset.color)
                    .repThemedListRow()
                } header: {
                    RepSectionHeader(title: "Exercises")
                } footer: {
                    Text("Hold an exercise, then move it to reorder. Keep holding to remove it. Sets, reps, and rest can be set after creation.")
                }
        }
        .repThemedList()
        .scrollClipDisabled()
        .contentMargins(.bottom, RepVisualSystem.pageSpacing, for: .scrollContent)
        .background(RepScreenBackground())
        .tint(colorPreset.color)
        .exerciseThumbnailScope {
            ExerciseThumbnailPrefetch.sources(from: selectedExercises, thumbnailSize: 34)
        }
        .navigationTitle("New Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: finish)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create", action: createRoutine)
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                    .accessibilityHint(canCreate ? "Saves this routine" : "Enter a routine name first")
            }
        }
        .onAppear {
            ExerciseThumbnailIdlePreloader.shared.cancel()
            isNameFocused = true
        }
        .onDisappear {
            ExercisePickerSessionCache.scheduleIdleThumbnailPrefetch()
        }
        .sheet(isPresented: $isChoosingExercise) {
            ExercisePickerView { exercise in
                selectedExercises.append(exercise)
                isChoosingExercise = false
            }
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
                guard let exercisePendingRemoval else { return }
                selectedExercises.removeAll { $0.id == exercisePendingRemoval.id }
                self.exercisePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { exercisePendingRemoval = nil }
        }
        .alert("Couldn’t create routine", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private func createRoutine() {
        let routine = Routine(
            name: trimmedName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            colorPreset: colorPreset
        )
        selectedExercises.enumerated().forEach { index, exercise in
            routine.appendExercise(RoutineExercise(
                exercise: exercise,
                orderIndex: index,
                targetSetCount: 3,
                suggestedRepetitions: 8,
                defaultRestSeconds: 90
            ))
        }
        modelContext.insert(routine)

        do {
            try modelContext.save()
            finish()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func finish() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
