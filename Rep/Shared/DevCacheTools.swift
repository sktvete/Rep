import Foundation
import SwiftData

#if DEBUG
@MainActor
enum DevCacheTools {
    static func clearCaches(in context: ModelContext) {
        URLCache.shared.removeAllCachedResponses()
        ExercisePickerSessionCache.invalidateAll()

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>()))?
            .filter { !$0.isArchived } ?? []
        ExercisePickerSessionCache.scheduleWarm(exercises: exercises, in: context)

        Task {
            await ExerciseThumbnailCache.shared.clearMemory()
        }
    }
}
#endif
