import SwiftData
import SwiftUI

/// Searchable exercise list for quickly adding existing exercises.
struct ExerciseQuickAddList: View {
    @Environment(\.modelContext) private var modelContext

    let exercises: [Exercise]
    var header: String?
    var footer: String?
    @Binding var isCreatingExercise: Bool
    var dismissOnSelect: Bool
    let onSelect: (Exercise) -> Void
    var onDismiss: (() -> Void)?

    @State private var searchText = ""
    @State private var detailExercise: Exercise?
    @State private var prepareTask: Task<Void, Never>?

    private var searchModel: ExercisePickerSearchModel { ExercisePickerSessionCache.searchModel }

    var body: some View {
        Group {
            if searchModel.displayed.isEmpty, !searchModel.isRefreshing, !ExercisePickerSessionCache.hasWarmBrowseList {
                ProgressView("Loading exercises…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchModel.displayed.isEmpty, !searchModel.isRefreshing {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    if let header {
                        Text(header)
                            .font(.subheadline)
                            .repSecondaryText()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(searchModel.displayed) { exercise in
                        ExercisePickerRow(
                            exercise: exercise,
                            onSelect: {
                                onSelect(exercise)
                                if dismissOnSelect {
                                    onDismiss?()
                                }
                            },
                            onShowDetails: { detailExercise = exercise }
                        )
                    }

                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       exercises.count > searchModel.displayed.count {
                        Text("Type to search \(exercises.count) exercises")
                            .font(.footnote)
                            .repSecondaryText()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    } else if let footer {
                        Text(footer)
                            .font(.footnote)
                            .repSecondaryText()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $searchText, prompt: "Name, nickname, muscle, or equipment")
        .sheet(isPresented: $isCreatingExercise) {
            CustomExerciseView { exercise in
                onSelect(exercise)
                if dismissOnSelect {
                    onDismiss?()
                }
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
        .onChange(of: exercises.count) { _, _ in
            ExercisePickerSessionCache.prepare(
                exercises: exercises,
                query: searchText,
                in: modelContext
            )
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
}
