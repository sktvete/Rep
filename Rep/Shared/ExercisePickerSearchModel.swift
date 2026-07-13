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
    private var catalogKey: UInt64 = 0
    private var usage: [UUID: Int] = [:]

    static let browseLimit = 120
    static let searchLimit = 150
    static let searchDebounce: Duration = .milliseconds(200)

    func setUsage(_ usage: [UUID: Int]) {
        guard self.usage != usage else { return }
        self.usage = usage
        index.invalidateBrowseOrder()
    }

    func prewarm(exercises: [Exercise]) {
        let available = exercises.filter { !$0.isArchived }
        index.prewarm(for: available)
    }

    func refresh(
        exercises: [Exercise],
        query: String,
        immediate: Bool = false
    ) {
        let available = exercises.filter { !$0.isArchived }
        let key = catalogKey(for: available)
        if key != catalogKey {
            catalogKey = key
            index.invalidateBrowseOrder()
            index.prewarm(for: available)
        }

        searchTask?.cancel()
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
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }

            isRefreshing = true
            let rankedIDs = await Task.detached(priority: .userInitiated) {
                ExerciseSearchEngine.searchIDs(
                    candidates,
                    query: trimmed,
                    usage: usageCopy,
                    limit: searchLimit
                )
            }.value
            guard !Task.isCancelled else { return }

            displayed = rankedIDs.compactMap { exerciseByID[$0] }
            isRefreshing = false
        }
    }

    private func catalogKey(for exercises: [Exercise]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(exercises.count)
        if let newest = exercises.max(by: { $0.updatedAt < $1.updatedAt }) {
            hasher.combine(newest.updatedAt)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}
