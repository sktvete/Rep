import Foundation
import SwiftData

@MainActor
enum RoutineColorSnapshotBackfillService {
    @discardableResult
    static func backfill(in context: ModelContext) throws -> Int {
        let routines = try context.fetch(FetchDescriptor<Routine>())
        var colorsByRoutineID: [UUID: RoutineColorPreset] = [:]
        colorsByRoutineID.reserveCapacity(routines.count)
        for routine in routines {
            colorsByRoutineID[routine.id] = routine.colorPreset
        }

        var updatedCount = 0
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) {
            guard session.routineColorPresetRaw == nil,
                  let routineID = session.routineID,
                  let color = colorsByRoutineID[routineID] else {
                continue
            }

            session.routineColorPreset = color
            updatedCount += 1
        }

        if updatedCount > 0 {
            try context.save()
        }
        return updatedCount
    }
}
