import SwiftUI

enum ExerciseThumbnailLoadPriority: Comparable, Sendable {
    case background
    case prefetch(listIndex: Int)
    case onScreen(listIndex: Int)

    private var rank: (Int, Int) {
        switch self {
        case .onScreen(let index): (0, index)
        case .prefetch(let index): (1, index)
        case .background: (2, Int.max)
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    var taskPriority: TaskPriority {
        switch self {
        case .onScreen: .userInitiated
        case .prefetch: .utility
        case .background: .background
        }
    }
}

@MainActor
final class ExerciseThumbnailScopeCenter {
    static let shared = ExerciseThumbnailScopeCenter()

    private var stack: [UUID] = []

    func push(_ id: UUID) {
        stack.removeAll { $0 == id }
        stack.append(id)
    }

    func pop(_ id: UUID) {
        stack.removeAll { $0 == id }
    }

    func isForeground(_ id: UUID) -> Bool {
        stack.last == id
    }

    func priority(
        scopeID: UUID,
        listIndex: Int?,
        isOnScreen: Bool
    ) -> ExerciseThumbnailLoadPriority {
        guard isForeground(scopeID) else { return .background }
        guard let listIndex else { return isOnScreen ? .onScreen(listIndex: 0) : .background }

        if isOnScreen {
            return .onScreen(listIndex: listIndex)
        }
        if listIndex <= ExerciseThumbnailListTracker.shared.maxVisibleIndex(for: scopeID) + 10 {
            return .prefetch(listIndex: listIndex)
        }
        return .background
    }
}

@MainActor
final class ExerciseThumbnailListTracker {
    static let shared = ExerciseThumbnailListTracker()

    private var maxVisibleIndexByScope: [UUID: Int] = [:]
    private var prefetchTask: Task<Void, Never>?

    func registerVisibleRow(scopeID: UUID, index: Int) {
        let current = maxVisibleIndexByScope[scopeID] ?? -1
        guard index > current else { return }
        maxVisibleIndexByScope[scopeID] = index
        schedulePrefetch(scopeID: scopeID)
    }

    func reset(scopeID: UUID) {
        maxVisibleIndexByScope[scopeID] = nil
    }

    func maxVisibleIndex(for scopeID: UUID) -> Int {
        maxVisibleIndexByScope[scopeID] ?? -1
    }

    func schedulePrefetch(
        scopeID: UUID,
        urls: [(index: Int, url: URL, maxPixel: CGFloat)]
    ) {
        guard ExerciseThumbnailScopeCenter.shared.isForeground(scopeID) else { return }
        let maxIndex = maxVisibleIndex(for: scopeID)
        guard maxIndex >= 0 else { return }

        let ahead = urls
            .filter { $0.index > maxIndex && $0.index <= maxIndex + 12 }
            .sorted { $0.index < $1.index }

        guard !ahead.isEmpty else { return }

        prefetchTask?.cancel()
        prefetchTask = Task {
            for item in ahead {
                guard !Task.isCancelled else { return }
                _ = await ExerciseThumbnailCache.shared.thumbnail(
                    for: item.url,
                    maxPixelSize: item.maxPixel,
                    priority: .prefetch(listIndex: item.index)
                )
            }
        }
    }

    private func schedulePrefetch(scopeID: UUID) {
        guard let urls = ExerciseThumbnailListTracker.registeredPrefetchSources[scopeID] else { return }
        schedulePrefetch(scopeID: scopeID, urls: urls())
    }

    fileprivate static var registeredPrefetchSources: [UUID: () -> [(index: Int, url: URL, maxPixel: CGFloat)]] = [:]
}

enum ExerciseThumbnailSizing {
    /// Point size used by exercise picker / add-exercise rows.
    static let pickerPointSize: CGFloat = 44

    /// Decode size shared by prefetch + on-screen picker rows so NSCache keys match.
    /// Cap at 64px — research shows list hitch is dominated by ImageIO decode cost;
    /// 44pt @2x is 88 but the 64 bucket is enough for this UI and halves pixel fill.
    @MainActor
    static var pickerMaxPixel: CGFloat {
        min(64, pickerPointSize * min(UIScreen.main.scale, 2))
    }

    static func canonicalPixelSize(_ requested: CGFloat) -> CGFloat {
        let requested = max(1, requested.rounded(.up))
        let buckets: [CGFloat] = [48, 64, 96, 128, 160, 192, 256]
        return buckets.first(where: { $0 >= requested }) ?? buckets.last ?? requested
    }

    static func cacheKey(url: URL, maxPixel: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(canonicalPixelSize(maxPixel)))"
    }
}

/// Process-wide decoded-thumbnail store. Thread-safe via `NSCache`, readable
/// synchronously from SwiftUI so prefetched rows paint without an async hop.
enum ExerciseThumbnailSyncCache {
    // NSCache is thread-safe; marked unsafe for Swift 6 static Sendable checks.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 320
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func store(_ image: UIImage, forKey key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    static func image(forKey key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    static func image(url: URL, maxPixel: CGFloat) -> UIImage? {
        image(forKey: ExerciseThumbnailSizing.cacheKey(url: url, maxPixel: maxPixel))
    }

    static func clear() {
        memory.removeAllObjects()
    }
}

enum ExerciseThumbnailPrefetch {
    @MainActor
    static func sources(
        from exercises: [Exercise],
        thumbnailSize: CGFloat
    ) -> [(index: Int, url: URL, maxPixel: CGFloat)] {
        let maxPixel = thumbnailSize == ExerciseThumbnailSizing.pickerPointSize
            ? ExerciseThumbnailSizing.pickerMaxPixel
            : thumbnailSize * min(UIScreen.main.scale, 2)
        return sources(from: exercises, maxPixel: maxPixel)
    }

    @MainActor
    static func sources(
        from exercises: [Exercise],
        maxPixel: CGFloat
    ) -> [(index: Int, url: URL, maxPixel: CGFloat)] {
        exercises.enumerated().compactMap { index, exercise in
            guard let url = ExerciseCatalogMedia.resolvedURL(for: exercise) else { return nil }
            return (index, url, maxPixel)
        }
    }

    /// Loads the leading picker rows into ``ExerciseThumbnailCache`` and awaits completion.
    @MainActor
    static func prefetchLeading(
        from exercises: [Exercise],
        count: Int = 12,
        thumbnailSize: CGFloat = ExerciseThumbnailSizing.pickerPointSize
    ) async {
        let sources = sources(
            from: Array(exercises.prefix(count)),
            thumbnailSize: thumbnailSize
        )
        guard !sources.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for item in sources {
                group.addTask {
                    _ = await ExerciseThumbnailCache.shared.thumbnail(
                        for: item.url,
                        maxPixelSize: item.maxPixel,
                        priority: .onScreen(listIndex: item.index)
                    )
                }
            }
        }
    }

    /// Fire-and-forget wrapper for non-launch call sites.
    @MainActor
    static func prefetchLeadingInBackground(
        from exercises: [Exercise],
        count: Int = 12,
        thumbnailSize: CGFloat = ExerciseThumbnailSizing.pickerPointSize
    ) {
        Task {
            await prefetchLeading(
                from: exercises,
                count: count,
                thumbnailSize: thumbnailSize
            )
        }
    }
}

/// Debounced, cancellable thumbnail warming for moments when the app has no user work.
///
/// Search-index warming is intentionally separate: building the local index never starts
/// network requests. The app can schedule this coordinator after the UI becomes idle and
/// cancel it as soon as typing, scrolling, a workout, or another interaction begins.
@MainActor
final class ExerciseThumbnailIdlePreloader {
    static let shared = ExerciseThumbnailIdlePreloader()

    private var task: Task<Void, Never>?

    func schedule(
        from exercises: [Exercise],
        count: Int = 16,
        thumbnailSize: CGFloat = 58,
        debounceNanoseconds: UInt64 = 250_000_000
    ) {
        let sources = ExerciseThumbnailPrefetch.sources(
            from: Array(exercises.prefix(max(0, count))),
            thumbnailSize: thumbnailSize
        )
        schedule(sources: sources, debounceNanoseconds: debounceNanoseconds)
    }

    func schedule(
        sources: [(index: Int, url: URL, maxPixel: CGFloat)],
        debounceNanoseconds: UInt64 = 250_000_000
    ) {
        task?.cancel()

        var seen = Set<URL>()
        let uniqueSources = sources.filter { seen.insert($0.url).inserted }
        guard !uniqueSources.isEmpty, canPrefetch else {
            task = nil
            return
        }

        task = Task(priority: .utility) { [uniqueSources] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled, canPrefetch else { return }

            // Deliberately sequential: idle warming must never compete with on-screen
            // rows for network, decoding, or memory bandwidth.
            for source in uniqueSources {
                guard !Task.isCancelled, canPrefetch else { return }
                _ = await ExerciseThumbnailCache.shared.thumbnail(
                    for: source.url,
                    maxPixelSize: source.maxPixel,
                    priority: .prefetch(listIndex: source.index)
                )
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private var canPrefetch: Bool {
        let processInfo = ProcessInfo.processInfo
        guard !processInfo.isLowPowerModeEnabled else { return false }
        switch processInfo.thermalState {
        case .serious, .critical:
            return false
        case .nominal, .fair:
            return true
        @unknown default:
            return false
        }
    }
}

private struct ExerciseThumbnailScopeIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var exerciseThumbnailScopeID: UUID? {
        get { self[ExerciseThumbnailScopeIDKey.self] }
        set { self[ExerciseThumbnailScopeIDKey.self] = newValue }
    }
}

extension View {
    func exerciseThumbnailScope(
        prefetchURLs: @escaping () -> [(index: Int, url: URL, maxPixel: CGFloat)] = { [] }
    ) -> some View {
        modifier(ExerciseThumbnailScopeModifier(prefetchURLs: prefetchURLs))
    }
}

private struct ExerciseThumbnailScopeModifier: ViewModifier {
    let prefetchURLs: () -> [(index: Int, url: URL, maxPixel: CGFloat)]
    @State private var scopeID = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.exerciseThumbnailScopeID, scopeID)
            .onAppear {
                ExerciseThumbnailScopeCenter.shared.push(scopeID)
                ExerciseThumbnailListTracker.registeredPrefetchSources[scopeID] = prefetchURLs
            }
            .onDisappear {
                ExerciseThumbnailScopeCenter.shared.pop(scopeID)
                ExerciseThumbnailListTracker.shared.reset(scopeID: scopeID)
                ExerciseThumbnailListTracker.registeredPrefetchSources[scopeID] = nil
            }
    }
}
