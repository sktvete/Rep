import SwiftUI

@MainActor
enum ExercisePickerThumbnailGate {
    static func disableThumbnails(_ thumbnailsEnabled: inout Bool, task: inout Task<Void, Never>?) {
        task?.cancel()
        thumbnailsEnabled = false
    }

    /// Browse / empty-workout lists show thumbs immediately when launch prefetch finished.
    /// Only search typing turns them off (to avoid decode storms while the query changes).
    static func configureForBrowse(
        thumbnailsEnabled: inout Bool,
        task: inout Task<Void, Never>?
    ) {
        task?.cancel()
        thumbnailsEnabled = true
    }

    static func scheduleReveal(
        thumbnailsEnabled: Binding<Bool>,
        isSearching: Bool,
        task: inout Task<Void, Never>?,
        delay: Duration = .milliseconds(180)
    ) {
        task?.cancel()
        guard !isSearching else {
            thumbnailsEnabled.wrappedValue = false
            ExerciseThumbnailIdlePreloader.shared.cancel()
            return
        }

        // Prefetch already decoded the leading rows — show them without an extra pause.
        if ExercisePickerSessionCache.leadingThumbnailsReady {
            thumbnailsEnabled.wrappedValue = true
            return
        }

        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            thumbnailsEnabled.wrappedValue = true
        }
    }
}
