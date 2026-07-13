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
    @State private var catalogService = ExerciseDBCatalogService()
    @State private var catalogSearchError: String?
    @State private var remoteSearchTask: Task<Void, Never>?
    @State private var thumbnailsEnabled = false
    @State private var prepareTask: Task<Void, Never>?
    @State private var thumbnailTask: Task<Void, Never>?

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
                                loadsImages: thumbnailsEnabled,
                                onSelect: { onSelect(exercise) },
                                onShowDetails: { detailExercise = exercise }
                            )
                        }

                        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           exercises.count > searchModel.displayed.count {
                            Text("Type to search \(exercises.count) exercises")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(RepScreenBackground())
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, nickname, muscle, or equipment")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                catalogStatus
            }
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
                ExercisePickerThumbnailGate.disableThumbnails(&thumbnailsEnabled, task: &thumbnailTask)
                schedulePrepare()
            }
            .onDisappear {
                prepareTask?.cancel()
                ExercisePickerThumbnailGate.disableThumbnails(&thumbnailsEnabled, task: &thumbnailTask)
            }
            .onChange(of: searchText) { _, newValue in
                ExercisePickerSessionCache.prepare(
                    exercises: exercises,
                    query: newValue,
                    in: modelContext
                )
                scheduleRemoteSearch(for: newValue)
            }
            .onChange(of: searchModel.isRefreshing) { _, isRefreshing in
                ExercisePickerThumbnailGate.scheduleReveal(
                    thumbnailsEnabled: $thumbnailsEnabled,
                    isSearching: isRefreshing,
                    task: &thumbnailTask
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
            guard !Task.isCancelled else { return }
            ExercisePickerThumbnailGate.scheduleReveal(
                thumbnailsEnabled: $thumbnailsEnabled,
                isSearching: searchModel.isRefreshing,
                task: &thumbnailTask
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

    @ViewBuilder
    private var catalogStatus: some View {
        let status = catalogStatusValues
        if status.isLoading || status.errorMessage != nil {
            ExerciseCatalogStatusView(
                isLoading: status.isLoading,
                progress: status.progress,
                errorMessage: status.errorMessage,
                onRetry: {
                    Task { await importRemoteSearchResults(debounce: false) }
                }
            )
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var catalogStatusValues: (isLoading: Bool, progress: Double?, errorMessage: String?) {
        switch catalogService.state {
        case .syncing(let progress):
            (true, progress.totalItems > 0 ? progress.fractionCompleted : nil, nil)
        case .failed(let message):
            (false, nil, catalogSearchError ?? message)
        case .idle, .complete:
            (false, nil, catalogSearchError)
        }
    }

    private func scheduleRemoteSearch(for query: String) {
        remoteSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            catalogSearchError = nil
            return
        }

        remoteSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await importRemoteSearchResults(debounce: false)
        }
    }

    private func importRemoteSearchResults(debounce: Bool) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else {
            catalogSearchError = nil
            return
        }

        do {
            if debounce {
                try await Task.sleep(for: .milliseconds(900))
            }
            try Task.checkCancellation()
            _ = try await catalogService.searchAndImport(query: query, in: modelContext)
            catalogSearchError = nil
            ExercisePickerSessionCache.prepare(
                exercises: exercises,
                query: searchText,
                in: modelContext
            )
        } catch is CancellationError {
            return
        } catch {
            catalogSearchError = "Online results aren’t available right now."
        }
    }
}
