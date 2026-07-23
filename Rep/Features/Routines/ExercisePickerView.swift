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
    @State private var remoteSearchGeneration: UInt64 = 0
    @State private var isRemoteSearching = false
    @State private var thumbnailsEnabled = ExercisePickerSessionCache.leadingThumbnailsReady
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
                        ForEach(Array(searchModel.displayed.enumerated()), id: \.element.id) { index, exercise in
                            ExercisePickerRow(
                                exercise: exercise,
                                loadsImages: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && thumbnailsEnabled,
                                listIndex: index,
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
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name, nickname, muscle, or equipment"
            )
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
            .exerciseThumbnailScope {
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
                remoteSearchGeneration &+= 1
                remoteSearchTask?.cancel()
                isRemoteSearching = false
            }
            .onChange(of: searchText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    ExercisePickerThumbnailGate.configureForBrowse(
                        thumbnailsEnabled: &thumbnailsEnabled,
                        task: &thumbnailTask
                    )
                } else {
                    ExercisePickerThumbnailGate.disableThumbnails(&thumbnailsEnabled, task: &thumbnailTask)
                }
                ExercisePickerSessionCache.prepare(
                    exercises: exercises,
                    query: newValue,
                    in: modelContext
                )
                scheduleRemoteSearch(for: newValue)
            }
            .onChange(of: searchModel.isRefreshing) { _, isRefreshing in
                guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
                    scheduleRemoteSearch(for: searchText, immediate: true)
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
            (isRemoteSearching, nil, catalogSearchError ?? message)
        case .idle, .complete:
            (isRemoteSearching, nil, catalogSearchError)
        }
    }

    private func scheduleRemoteSearch(for query: String, immediate: Bool = false) {
        remoteSearchGeneration &+= 1
        let generation = remoteSearchGeneration
        remoteSearchTask?.cancel()
        isRemoteSearching = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            catalogSearchError = nil
            return
        }

        remoteSearchTask = Task {
            do {
                if !immediate {
                    try await Task.sleep(for: .milliseconds(300))
                }
                try Task.checkCancellation()
                guard generation == remoteSearchGeneration else { return }
                isRemoteSearching = true

                _ = try await catalogService.searchAndImport(query: trimmed, in: modelContext)
                try Task.checkCancellation()
                guard generation == remoteSearchGeneration,
                      trimmed == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                catalogSearchError = nil
                ExercisePickerSessionCache.prepare(
                    exercises: exercises,
                    query: searchText,
                    in: modelContext
                )
                isRemoteSearching = false
            } catch is CancellationError {
                if generation == remoteSearchGeneration {
                    isRemoteSearching = false
                }
            } catch {
                if generation == remoteSearchGeneration {
                    isRemoteSearching = false
                    catalogSearchError = "Online results aren’t available right now."
                }
            }
        }
    }
}
