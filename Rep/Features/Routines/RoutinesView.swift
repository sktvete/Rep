import SwiftData
import SwiftUI

struct RoutinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.updatedAt, order: .reverse) private var routines: [Routine]

    @State private var isCreatingRoutine = false
    @State private var showsArchivedRoutines = false
    @State private var routinePendingDeletion: Routine?
    @State private var operationError: String?

    private let onStartRoutine: (Routine) -> Void

    init(onStartRoutine: @escaping (Routine) -> Void = { _ in }) {
        self.onStartRoutine = onStartRoutine
    }

    private var visibleRoutines: [Routine] {
        routines.filter { showsArchivedRoutines || !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RepScreenBackground()

                Group {
                    if visibleRoutines.isEmpty {
                        ContentUnavailableView {
                            Label(
                                showsArchivedRoutines ? "No archived routines" : "No routines yet",
                                systemImage: "list.bullet.rectangle"
                            )
                        } description: {
                            Text(
                                showsArchivedRoutines
                                    ? "Archived routines will appear here."
                                    : "Save the exercises you train together, then start in one tap."
                            )
                        } actions: {
                            if !showsArchivedRoutines {
                                Button("Create Routine", systemImage: "plus") { isCreatingRoutine = true }
                                    .repPrimaryButton()
                                    .controlSize(.large)
                            }
                        }
                    } else {
                        List {
                            Section {
                                ForEach(visibleRoutines) { routine in
                                    RoutineListRow(
                                        routine: routine,
                                        onStart: { onStartRoutine(routine) }
                                    )
                                    .repThemedListRow()
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            routinePendingDeletion = routine
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }

                                        Button {
                                            setArchived(!routine.isArchived, for: routine)
                                        } label: {
                                            Label(
                                                routine.isArchived ? "Restore" : "Archive",
                                                systemImage: routine.isArchived ? "tray.and.arrow.up" : "archivebox"
                                            )
                                        }
                                        .tint(.orange)
                                    }
                                    .contextMenu {
                                        Button {
                                            duplicate(routine)
                                        } label: {
                                            Label("Duplicate", systemImage: "plus.square.on.square")
                                        }

                                        Button {
                                            setArchived(!routine.isArchived, for: routine)
                                        } label: {
                                            Label(
                                                routine.isArchived ? "Restore" : "Archive",
                                                systemImage: routine.isArchived ? "tray.and.arrow.up" : "archivebox"
                                            )
                                        }

                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            routinePendingDeletion = routine
                                        }
                                    }
                                }
                            } header: {
                                RepSectionHeader(title: showsArchivedRoutines ? "All Routines" : "Your Routines")
                            } footer: {
                                Text("Swipe a routine for archive and delete options. Touch and hold to duplicate it.")
                            }
                        }
                        .repThemedList()
                    }
                }
            }
            .repMainNavigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Show Archived", isOn: $showsArchivedRoutines)
                    } label: {
                        Label("Routine options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingRoutine = true
                    } label: {
                        Label("New Routine", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingRoutine) {
                CreateRoutineView()
            }
            .alert(
                "Delete routine?",
                isPresented: Binding(
                    get: { routinePendingDeletion != nil },
                    set: { if !$0 { routinePendingDeletion = nil } }
                ),
                presenting: routinePendingDeletion
            ) { routine in
                Button("Delete", role: .destructive) { delete(routine) }
                Button("Cancel", role: .cancel) {}
            } message: { routine in
                Text("“\(routine.name)” will be removed. Past workouts will not be changed.")
            }
            .alert("Couldn’t update routines", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationError ?? "Please try again.")
            }
        }
    }

    private func duplicate(_ source: Routine) {
        let copy = Routine(
            name: "\(source.name) Copy",
            notes: source.notes,
            colorPreset: source.colorPreset
        )
        let copiedExercises = source.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .enumerated()
            .map { index, item in
                RoutineExercise(
                    exercise: item.exercise,
                    orderIndex: index,
                    targetSetCount: item.targetSetCount,
                    suggestedRepetitions: item.suggestedRepetitions,
                    defaultRestSeconds: item.defaultRestSeconds,
                    notes: item.notes,
                    supersetGroupIdentifier: item.supersetGroupIdentifier
                )
            }
        copiedExercises.forEach { copy.appendExercise($0) }
        modelContext.insert(copy)
        persist()
    }

    private func setArchived(_ isArchived: Bool, for routine: Routine) {
        routine.isArchived = isArchived
        routine.updatedAt = .now
        persist()
    }

    private func delete(_ routine: Routine) {
        modelContext.delete(routine)
        routinePendingDeletion = nil
        persist()
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct RoutineListRow: View {
    let routine: Routine
    let onStart: () -> Void

    private var exerciseNames: String {
        let names = routine.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(3)
            .compactMap { $0.exercise?.name }
        return names.isEmpty ? "No exercises" : names.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink {
                RoutineEditorView(routine: routine, onStartRoutine: onStart)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: routine.isArchived ? "archivebox.fill" : "figure.strengthtraining.traditional")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(routine.isArchived ? Color.secondary : routine.colorPreset.color)
                        .frame(width: 38, height: 38)
                        .background(
                            routine.isArchived ? Color.secondary.opacity(0.1) : routine.colorPreset.color.opacity(0.13),
                            in: .rect(cornerRadius: 11)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(routine.name)
                                .font(.headline)
                            if routine.isArchived {
                                Text("Archived")
                                    .font(.caption2.weight(.semibold))
                                    .repSecondaryText()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text(exerciseNames)
                            .font(.subheadline)
                            .repSecondaryText()
                            .lineLimit(1)
                        Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !routine.isArchived {
                Button("Start", systemImage: "play.fill", action: onStart)
                    .labelStyle(.iconOnly)
                    .repSecondaryButton()
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Start \(routine.name)")
                    .accessibilityHint("Begins this routine")
            }
        }
    }
}

#Preview {
    RoutinesView()
        .modelContainer(for: [Routine.self, RoutineExercise.self, Exercise.self], inMemory: true)
}
