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
    @State private var thumbnailsEnabled = ExercisePickerSessionCache.leadingThumbnailsReady
    @State private var prepareTask: Task<Void, Never>?
    @State private var thumbnailTask: Task<Void, Never>?

    private var searchModel: ExercisePickerSearchModel { ExercisePickerSessionCache.searchModel }

    private var isBrowsing: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Browse may paint from the launch cache; search stays placeholder-only to avoid hitch.
    private var shouldLoadThumbnails: Bool {
        guard isBrowsing else { return false }
        return thumbnailsEnabled || ExercisePickerSessionCache.leadingThumbnailsReady
    }

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

                    ForEach(Array(searchModel.displayed.enumerated()), id: \.element.id) { index, exercise in
                        ExercisePickerRow(
                            exercise: exercise,
                            loadsImages: shouldLoadThumbnails,
                            listIndex: index,
                            onSelect: {
                                onSelect(exercise)
                                if dismissOnSelect {
                                    onDismiss?()
                                }
                            },
                            onShowDetails: { detailExercise = exercise }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    if isBrowsing,
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Name, nickname, muscle, or equipment"
        )
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
        .exerciseThumbnailScope {
            // Lower LOD than detail views — list stutter is dominated by decode cost.
            ExerciseThumbnailPrefetch.sources(
                from: searchModel.displayed,
                thumbnailSize: ExerciseThumbnailSizing.pickerPointSize
            )
        }
        .onAppear {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ExercisePickerThumbnailGate.configureForBrowse(
                    thumbnailsEnabled: &thumbnailsEnabled,
                    task: &thumbnailTask
                )
            }
            schedulePrepare()
        }
        .onDisappear {
            prepareTask?.cancel()
            thumbnailTask?.cancel()
        }
        .onChange(of: searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ExercisePickerThumbnailGate.configureForBrowse(
                    thumbnailsEnabled: &thumbnailsEnabled,
                    task: &thumbnailTask
                )
            } else {
                // Search results stay placeholder-only — decode is the hitch source.
                ExercisePickerThumbnailGate.disableThumbnails(&thumbnailsEnabled, task: &thumbnailTask)
            }
            ExercisePickerSessionCache.prepare(
                exercises: exercises,
                query: newValue,
                in: modelContext
            )
        }
        .onChange(of: searchModel.isRefreshing) { _, isRefreshing in
            // Only reveal thumbs when browsing; never after a search settle.
            guard isBrowsing else { return }
            ExercisePickerThumbnailGate.scheduleReveal(
                thumbnailsEnabled: $thumbnailsEnabled,
                isSearching: isRefreshing,
                task: &thumbnailTask
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
            guard !Task.isCancelled else { return }
            ExercisePickerThumbnailGate.scheduleReveal(
                thumbnailsEnabled: $thumbnailsEnabled,
                isSearching: searchModel.isRefreshing,
                task: &thumbnailTask
            )
        }
    }
}
