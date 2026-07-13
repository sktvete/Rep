import Foundation
import SwiftData

/// Session-wide cache so exercise pickers open instantly after the first warm-up.
@MainActor
enum ExercisePickerSessionCache {
    static let searchModel = ExercisePickerSearchModel()
    private static var usage: [UUID: Int] = [:]
    private static var isWarmed = false
    private static var warmTask: Task<Void, Never>?

    static var hasWarmBrowseList: Bool { isWarmed && !searchModel.displayed.isEmpty }

    static func warm(exercises: [Exercise], in context: ModelContext) {
        guard !isWarmed else { return }
        usage = ExerciseUsageService.cachedCounts(in: context)
        searchModel.setUsage(usage)
        searchModel.prewarm(exercises: exercises)
        searchModel.refresh(exercises: exercises, query: "", immediate: true)
        isWarmed = true
    }

    static func scheduleWarm(exercises: [Exercise], in context: ModelContext) {
        guard !isWarmed else { return }
        warmTask?.cancel()
        warmTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            warm(exercises: exercises, in: context)
        }
    }

    static func prepare(exercises: [Exercise], query: String, in context: ModelContext) {
        if !isWarmed {
            usage = ExerciseUsageService.cachedCounts(in: context)
            searchModel.setUsage(usage)
            isWarmed = true
        }
        searchModel.refresh(exercises: exercises, query: query, immediate: query.isEmpty)
    }

    static func invalidateUsage() {
        ExerciseUsageService.invalidateCache()
        usage = [:]
        isWarmed = false
        searchModel.setUsage([:])
    }
}
