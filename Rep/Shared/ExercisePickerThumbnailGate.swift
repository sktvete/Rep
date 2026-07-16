import SwiftUI

@MainActor
enum ExercisePickerThumbnailGate {
    static func disableThumbnails(_ thumbnailsEnabled: inout Bool, task: inout Task<Void, Never>?) {
        task?.cancel()
        thumbnailsEnabled = false
    }

    static func scheduleReveal(
        thumbnailsEnabled: Binding<Bool>,
        isSearching: Bool,
        task: inout Task<Void, Never>?,
        delay: Duration = .milliseconds(350)
    ) {
        task?.cancel()
        guard !isSearching else {
            thumbnailsEnabled.wrappedValue = false
            return
        }

        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            thumbnailsEnabled.wrappedValue = true
        }
    }
}
