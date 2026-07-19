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

enum ExerciseThumbnailPrefetch {
    @MainActor
    static func sources(
        from exercises: [Exercise],
        thumbnailSize: CGFloat
    ) -> [(index: Int, url: URL, maxPixel: CGFloat)] {
        let displayScale = UIScreen.main.scale
        let maxPixel = thumbnailSize * max(1, displayScale)
        return exercises.enumerated().compactMap { index, exercise in
            guard let value = exercise.mediaURLString,
                  !value.isEmpty,
                  let url = URL(string: value)
            else { return nil }
            return (index, url, maxPixel)
        }
    }

    /// Loads the leading picker rows into `ExerciseThumbnailCache` so Add Exercise opens warm.
    @MainActor
    static func prefetchLeading(
        from exercises: [Exercise],
        count: Int = 10,
        thumbnailSize: CGFloat = 58
    ) {
        let sources = sources(
            from: Array(exercises.prefix(count)),
            thumbnailSize: thumbnailSize
        )
        guard !sources.isEmpty else { return }

        Task {
            for item in sources {
                guard !Task.isCancelled else { return }
                _ = await ExerciseThumbnailCache.shared.thumbnail(
                    for: item.url,
                    maxPixelSize: item.maxPixel,
                    priority: .prefetch(listIndex: item.index)
                )
            }
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
