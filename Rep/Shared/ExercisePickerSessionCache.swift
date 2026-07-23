import Foundation
import SwiftData

/// Session-wide cache so exercise pickers open instantly after the first warm-up.
@MainActor
enum ExercisePickerSessionCache {
    static let searchModel = ExercisePickerSearchModel()
    private static var usage: [UUID: Int] = [:]
    private static var isWarmed = false
    private static var warmTask: Task<Void, Never>?
    private static var didPrefetchLeadingThumbnails = false

    static var hasWarmBrowseList: Bool { isWarmed && !searchModel.displayed.isEmpty }
    static var leadingThumbnailsReady: Bool { didPrefetchLeadingThumbnails }

    static func warm(exercises: [Exercise], in context: ModelContext) {
        guard !isWarmed else { return }
        usage = ExerciseUsageService.cachedCounts(in: context)
        searchModel.setUsage(usage)
        searchModel.prewarm(exercises: exercises)
        searchModel.refresh(exercises: exercises, query: "", immediate: true)
        isWarmed = true
    }

    /// Warms the search index and awaits leading thumbnail decode before returning.
    static func warmAndPrefetchLeading(
        exercises: [Exercise],
        in context: ModelContext,
        count: Int = 12
    ) async {
        if !isWarmed {
            warm(exercises: exercises, in: context)
        }
        let sources = searchModel.displayed.isEmpty ? exercises : searchModel.displayed
        let leading = Array(sources.prefix(count))
        let prefetchSources = ExerciseThumbnailPrefetch.sources(
            from: leading,
            thumbnailSize: ExerciseThumbnailSizing.pickerPointSize
        )
        let needsDecode = prefetchSources.contains {
            ExerciseThumbnailSyncCache.image(url: $0.url, maxPixel: $0.maxPixel) == nil
        }
        if !needsDecode, didPrefetchLeadingThumbnails {
            return
        }
        await ExerciseThumbnailPrefetch.prefetchLeading(
            from: leading,
            count: count,
            thumbnailSize: ExerciseThumbnailSizing.pickerPointSize
        )
        didPrefetchLeadingThumbnails = true
    }

    static func scheduleWarm(
        exercises: [Exercise],
        in context: ModelContext,
        prefetchLeadingThumbnails: Int = 12
    ) {
        warmTask?.cancel()
        warmTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await warmAndPrefetchLeading(
                exercises: exercises,
                in: context,
                count: prefetchLeadingThumbnails
            )
        }
    }

    static func prepare(exercises: [Exercise], query: String, in context: ModelContext) {
        if !isWarmed {
            usage = ExerciseUsageService.cachedCounts(in: context)
            searchModel.setUsage(usage)
            searchModel.prewarm(exercises: exercises)
            isWarmed = true
        }
        searchModel.refresh(exercises: exercises, query: query, immediate: query.isEmpty)
        if !query.isEmpty { cancelIdleThumbnailPrefetch() }
    }

    /// Starts only the optional network warm-up. Local search/index preparation above
    /// stays synchronous and network-free so opening the builder or picker remains fast.
    static func scheduleIdleThumbnailPrefetch(
        count: Int = 16,
        thumbnailSize: CGFloat = ExerciseThumbnailSizing.pickerPointSize
    ) {
        guard isWarmed, !searchModel.displayed.isEmpty else { return }
        ExerciseThumbnailIdlePreloader.shared.schedule(
            from: searchModel.displayed,
            count: count,
            thumbnailSize: thumbnailSize
        )
    }

    static func cancelIdleThumbnailPrefetch() {
        ExerciseThumbnailIdlePreloader.shared.cancel()
    }

    static func invalidateUsage() {
        ExerciseUsageService.invalidateCache()
        usage = [:]
        isWarmed = false
        didPrefetchLeadingThumbnails = false
        cancelIdleThumbnailPrefetch()
        searchModel.setUsage([:])
    }

    static func invalidateAll() {
        warmTask?.cancel()
        warmTask = nil
        ExerciseUsageService.invalidateCache()
        usage = [:]
        isWarmed = false
        didPrefetchLeadingThumbnails = false
        cancelIdleThumbnailPrefetch()
        searchModel.reset()
    }
}
