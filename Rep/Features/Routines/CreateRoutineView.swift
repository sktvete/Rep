import SwiftData
import SwiftUI

struct CreateRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notes = ""
    @State private var selectedExercises: [Exercise] = []
    @State private var isChoosingExercise = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        LabeledContent {
                            TextField("Routine name", text: $name)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                        } label: {
                            Label("Name", systemImage: "textformat")
                        }

                        Divider().padding(.vertical, 12)

                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    .repThemedListSection()
                } header: {
                    RepSectionHeader(title: "Routine")
                }

                Section {
                    ForEach(selectedExercises) { exercise in
                        HStack(spacing: 12) {
                            ExerciseMediaThumbnail(exercise: exercise, size: 34)
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
                    }
                    .repThemedListRow()
                } header: {
                    HStack {
                        RepSectionHeader(title: "Exercises")
                        Spacer()
                        if selectedExercises.count > 1 { EditButton().textCase(nil) }
                    }
                } footer: {
                    Text("You can configure sets, repetitions, and rest after creating the routine.")
                }
            }
            .repThemedList()
            .background(RepScreenBackground())
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createRoutine)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
