import Foundation
import Observation
import SwiftUI

/// Debounced, cached exercise-picker search state.
///
/// Typing stays instant because results update only after a short pause, and the
/// previous list stays visible while the user is still composing a query.
@MainActor
@Observable
final class ExercisePickerSearchModel {
    private(set) var displayed: [Exercise] = []
    private(set) var isRefreshing = false

    private let index = ExerciseSearchIndex()
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
    private var catalogKey: UInt64 = 0
    private var usage: [UUID: Int] = [:]

    static let browseLimit = 80
    static let searchLimit = 48
    /// Short enough to feel live; long enough that mid-word keystrokes cancel prior work.
    static let searchDebounce: Duration = .milliseconds(120)

    func setUsage(_ usage: [UUID: Int]) {
        guard self.usage != usage else { return }
        self.usage = usage
        index.invalidateBrowseOrder()
    }

    func prewarm(exercises: [Exercise]) {
        let available = availableExercises(from: exercises)
        index.prewarm(for: available)
    }

    func refresh(
        exercises: [Exercise],
        query: String,
        immediate: Bool = false
    ) {
        let available = availableExercises(from: exercises)
        let key = catalogKey(for: available)
        if key != catalogKey {
            catalogKey = key
            index.invalidateBrowseOrder()
            index.prewarm(for: available)
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        isRefreshing = false
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            displayed = index.browseOrder(
                for: available,
                usage: usage,
                limit: Self.browseLimit
            )
            isRefreshing = false
            return
        }

        let delay: Duration = immediate ? .zero : Self.searchDebounce
        let candidates = index.candidates(for: available)
        let usageCopy = usage
        let exerciseByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        let searchLimit = Self.searchLimit

        searchTask = Task {
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
                guard generation == searchGeneration else { return }

                isRefreshing = true
                let worker = Task.detached(priority: .userInitiated) {
                    try ExerciseSearchEngine.searchIDsCancellable(
                        candidates,
                        query: trimmed,
                        usage: usageCopy,
                        limit: searchLimit
                    )
                }
                let rankedIDs = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard generation == searchGeneration else { return }

                displayed = rankedIDs.compactMap { exerciseByID[$0] }
                isRefreshing = false
            } catch is CancellationError {
                if generation == searchGeneration {
                    isRefreshing = false
                }
            } catch {
                if generation == searchGeneration {
                    isRefreshing = false
                }
            }
        }
    }

    func reset() {
        searchGeneration &+= 1
        searchTask?.cancel()
        displayed = []
        isRefreshing = false
        catalogKey = 0
        usage = [:]
        index.rebuildDocuments(for: [])
        index.invalidateBrowseOrder()
    }

    private func catalogKey(for exercises: [Exercise]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(exercises.count)
        if let newest = exercises.max(by: { $0.updatedAt < $1.updatedAt }) {
            hasher.combine(newest.updatedAt)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private func availableExercises(from exercises: [Exercise]) -> [Exercise] {
        ExerciseCatalogIdentity.deduplicated(
            exercises.filter { !$0.isArchived },
            usage: usage
        )
    }
}
