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
                    VStack(alignment: .leading, spacing: 20) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(colorPreset.color.gradient)
                            .frame(height: 6)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.caption.weight(.semibold))
                                .repSecondaryText()
                            TextField("Push, Pull, Legs…", text: $name)
                                .font(.title3.weight(.semibold))
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.caption.weight(.semibold))
                                .repSecondaryText()
                            TextField("Optional context for this routine", text: $notes, axis: .vertical)
                                .lineLimit(2...5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Color")
                                .font(.caption.weight(.semibold))
                                .repSecondaryText()
                            RoutineColorPicker(selection: $colorPreset)
                        }
                    }
                    .repThemedListSection()
                } header: {
                    RepSectionHeader(title: "Routine")
                }

                Section {
                    if selectedExercises.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(colorPreset.color)
                            Text("No exercises yet")
                                .font(.headline)
                            Text("Add the movements you train together. Sets, reps, and rest can wait until after you create it.")
                                .font(.subheadline)
                                .repSecondaryText()
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                isChoosingExercise = true
                            } label: {
                                Label("Add Exercise", systemImage: "plus.circle.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .repPrimaryButton()
                            .tint(colorPreset.color)
                            .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .repThemedListSection(padding: 22)
                    } else {
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
                    }
                } header: {
                    HStack {
                        RepSectionHeader(title: "Exercises")
                        Spacer()
                        if selectedExercises.count > 1 {
                            EditButton().textCase(nil)
                        }
                    }
                } footer: {
                    if !selectedExercises.isEmpty {
                        Text("You can configure sets, repetitions, and rest after creating the routine.")
                    }
                }
            }
            .repThemedList()
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
                    Button(action: createRoutine) {
                        Text("Create")
                            .fontWeight(.semibold)
                            .foregroundStyle(canCreate ? colorPreset.color : Color.primary.opacity(0.45))
                    }
                    .disabled(!canCreate)
                    .accessibilityHint(canCreate ? "Saves this routine" : "Enter a routine name first")
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
