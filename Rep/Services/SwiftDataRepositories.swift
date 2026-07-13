import Foundation
import SwiftData

@MainActor
final class SwiftDataExerciseRepository: ExerciseRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all(includeArchived: Bool = false) throws -> [Exercise] {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        let result = try context.fetch(descriptor)
        return includeArchived ? result : result.filter { !$0.isArchived }
    }

    func exercise(id: UUID) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == id }
    }

    func hasExercise(named name: String, excluding id: UUID? = nil) throws -> Bool {
        let normalized = ExerciseNameNormalizer.normalize(name)
        return try context.fetch(FetchDescriptor<Exercise>()).contains {
            $0.normalizedName == normalized && $0.id != id
        }
    }

    func insert(_ exercise: Exercise) throws { context.insert(exercise); try context.save() }
    func delete(_ exercise: Exercise) throws { context.delete(exercise); try context.save() }
    func save() throws { try context.save() }
}

@MainActor
final class SwiftDataRoutineRepository: RoutineRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all(includeArchived: Bool = false) throws -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let result = try context.fetch(descriptor)
        return includeArchived ? result : result.filter { !$0.isArchived }
    }

    func routine(id: UUID) throws -> Routine? {
        try context.fetch(FetchDescriptor<Routine>()).first { $0.id == id }
    }

    func insert(_ routine: Routine) throws { context.insert(routine); try context.save() }
    func delete(_ routine: Routine) throws { context.delete(routine); try context.save() }
    func save() throws { try context.save() }
}

@MainActor
final class SwiftDataWorkoutRepository: WorkoutRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func activeSession() throws -> WorkoutSession? {
        try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.state == .active }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func completedSessions() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.state == .completed }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
    }

    func allSessions() throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
    }

    func insert(_ session: WorkoutSession) throws { context.insert(session); try context.save() }
    func delete(_ session: WorkoutSession) throws { context.delete(session); try context.save() }
    func save() throws { try context.save() }
}

@MainActor
final class SwiftDataBodyweightRepository: BodyweightRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func entries() throws -> [BodyweightEntry] {
        try context.fetch(FetchDescriptor<BodyweightEntry>(sortBy: [SortDescriptor(\.measuredAt, order: .reverse)]))
    }

    func insert(_ entry: BodyweightEntry) throws { context.insert(entry); try context.save() }
    func delete(_ entry: BodyweightEntry) throws { context.delete(entry); try context.save() }
    func save() throws { try context.save() }
}
