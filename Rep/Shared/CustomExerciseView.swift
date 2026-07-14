import SwiftData
import SwiftUI

struct CustomExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]

    let onCreated: (Exercise) -> Void

    @State private var name = ""
    @State private var primaryMuscle: MuscleGroup = .other
    @State private var equipment: Equipment = .other
    @State private var measurementType: MeasurementType = .weightAndRepetitions
    @State private var notes = ""
    @State private var duplicate: Exercise?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Primary Muscle", selection: $primaryMuscle) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Picker("Track", selection: $measurementType) {
                        ForEach(MeasurementType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional setup or instructions", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Custom Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addExercise)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Exercise already exists", isPresented: Binding(
                get: { duplicate != nil },
                set: { if !$0 { duplicate = nil } }
            ), presenting: duplicate) { exercise in
                Button("Use Existing") { finish(with: exercise) }
                Button("Keep Editing", role: .cancel) {}
            } message: { exercise in
                Text("“\(exercise.name)” is already in your library. Similar variations can use a more specific name.")
            }
            .alert("Couldn’t add exercise", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addExercise() {
        let normalized = ExerciseNameNormalizer.normalize(trimmedName)
        if let existing = exercises.first(where: { $0.normalizedName == normalized }) {
            duplicate = existing
            return
        }

        let exercise = Exercise(
            name: trimmedName,
            primaryMuscleGroup: primaryMuscle,
            equipment: equipment,
            measurementType: measurementType,
            isCustom: true,
            userNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(exercise)
        do {
            try modelContext.save()
            finish(with: exercise)
        } catch {
            AppLog.persistenceFailure(operation: "Create custom exercise", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func finish(with exercise: Exercise) {
        onCreated(exercise)
        dismiss()
    }
}
