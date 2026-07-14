import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Exercise> { $0.isArchived == false }, sort: \Exercise.name)
    private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var isCreatingExercise = false
    @State private var detailExercise: Exercise?
    @State private var prepareTask: Task<Void, Never>?

    private var searchModel: ExercisePickerSearchModel { ExercisePickerSessionCache.searchModel }

    let onSelect: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises available", systemImage: "dumbbell")
                    } description: {
                        Text("Add an exercise to begin building this routine.")
                    } actions: {
                        Button("New Exercise", systemImage: "plus") { isCreatingExercise = true }
                            .repPrimaryButton()
                            .controlSize(.large)
                    }
                } else if searchModel.displayed.isEmpty, !searchModel.isRefreshing, !ExercisePickerSessionCache.hasWarmBrowseList {
                    ProgressView("Loading exercises…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchModel.displayed.isEmpty, !searchModel.isRefreshing {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(searchModel.displayed) { exercise in
                            ExercisePickerRow(
                                exercise: exercise,
                                onSelect: { onSelect(exercise) },
                                onShowDetails: { detailExercise = exercise }
                            )
                            .repThemedListRow(padding: 12)
                        }

                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           exercises.count > searchModel.displayed.count {
                            Text("Type to search \(exercises.count) exercises")
                                .font(.footnote)
                                .repSecondaryText()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .repThemedList()
                }
            }
            .background(RepScreenBackground())
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, nickname, muscle, or equipment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Exercise", systemImage: "plus") {
                        isCreatingExercise = true
                    }
                }
            }
            .sheet(isPresented: $isCreatingExercise) {
                CustomExerciseView { exercise in
                    onSelect(exercise)
                }
            }
            .sheet(item: $detailExercise) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .onAppear {
                schedulePrepare()
            }
            .onDisappear {
                prepareTask?.cancel()
            }
            .onChange(of: searchText) { _, newValue in
                ExercisePickerSessionCache.prepare(
                    exercises: exercises,
                    query: newValue,
                    in: modelContext
                )
            }
            .onChange(of: exerciseCatalogSignature) { _, _ in
                ExercisePickerSessionCache.prepare(
                    exercises: exercises,
                    query: searchText,
                    in: modelContext
                )
            }
        }
    }

    private func schedulePrepare() {
        prepareTask?.cancel()
        prepareTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            ExercisePickerSessionCache.prepare(
                exercises: exercises,
                query: searchText,
                in: modelContext
            )
        }
    }

    private var exerciseCatalogSignature: Int {
        var hasher = Hasher()
        hasher.combine(exercises.count)
        if let last = exercises.last {
            hasher.combine(last.id)
            hasher.combine(last.updatedAt)
        }
        return hasher.finalize()
    }

}
