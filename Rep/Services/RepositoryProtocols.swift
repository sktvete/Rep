import Foundation

@MainActor
protocol ExerciseRepository {
    func all(includeArchived: Bool) throws -> [Exercise]
    func exercise(id: UUID) throws -> Exercise?
    func hasExercise(named name: String, excluding id: UUID?) throws -> Bool
    func insert(_ exercise: Exercise) throws
    func delete(_ exercise: Exercise) throws
    func save() throws
}

@MainActor
protocol RoutineRepository {
    func all(includeArchived: Bool) throws -> [Routine]
    func routine(id: UUID) throws -> Routine?
    func insert(_ routine: Routine) throws
    func delete(_ routine: Routine) throws
    func save() throws
}

@MainActor
protocol WorkoutRepository {
    func activeSession() throws -> WorkoutSession?
    func completedSessions() throws -> [WorkoutSession]
    func allSessions() throws -> [WorkoutSession]
    func insert(_ session: WorkoutSession) throws
    func delete(_ session: WorkoutSession) throws
    func save() throws
}

@MainActor
protocol BodyweightRepository {
    func entries() throws -> [BodyweightEntry]
    func insert(_ entry: BodyweightEntry) throws
    func delete(_ entry: BodyweightEntry) throws
    func save() throws
}
