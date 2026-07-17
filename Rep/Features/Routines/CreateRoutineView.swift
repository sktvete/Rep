import SwiftData
import SwiftUI

struct CreateRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notes = ""
    @State private var colorPreset: RoutineColorPreset = .blue
    @State private var selectedExercises: [Exercise] = []
    @State private var isChoosingExercise = false
    @State private var saveError: String?
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
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
                    ForEach(Array(selectedExercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(spacing: 12) {
                            ExerciseMediaThumbnail(exercise: exercise, size: 34, listIndex: index)
                            Text(exercise.name)
                                .fontWeight(.medium)
                        }
                        .repThemedListRow(padding: 12)
                    }
                    .onDelete { selectedExercises.remove(atOffsets: $0) }
                    .onMove { selectedExercises.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        isChoosingExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(colorPreset.color)
                    .repThemedListRow()
                } header: {
                    HStack {
                        RepSectionHeader(title: "Exercises")
                        Spacer()
                        if selectedExercises.count > 1 {
                            EditButton().textCase(nil)
                        }
                    }
                } footer: {
                    Text("Sets, reps, and rest can be set after you create the routine.")
                }
            }
            .repThemedList()
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createRoutine)
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                        .accessibilityHint(canCreate ? "Saves this routine" : "Enter a routine name first")
                }
            }
            .onAppear {
                isNameFocused = true
            }
            .sheet(isPresented: $isChoosingExercise) {
                ExercisePickerView { exercise in
                    selectedExercises.append(exercise)
                    isChoosingExercise = false
                }
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
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
