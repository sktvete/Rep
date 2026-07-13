import Foundation
import SwiftData

@MainActor
enum ExerciseSeedService {
    private struct Seed {
        let name: String
        let muscle: MuscleGroup
        let secondary: [MuscleGroup]
        let equipment: Equipment
        let measurement: MeasurementType
        let aliases: [String]

        init(
            _ name: String,
            _ muscle: MuscleGroup,
            _ equipment: Equipment,
            _ measurement: MeasurementType = .weightAndRepetitions,
            secondary: [MuscleGroup] = [],
            aliases: [String] = []
        ) {
            self.name = name
            self.muscle = muscle
            self.secondary = secondary
            self.equipment = equipment
            self.measurement = measurement
            self.aliases = aliases
        }
    }

    @discardableResult
    static func seedIfNeeded(in context: ModelContext) throws -> [Exercise] {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingNames = Set(existing.map(\.normalizedName))
        let missing = seeds.filter { !existingNames.contains(ExerciseNameNormalizer.normalize($0.name)) }
        let exercises = missing.map {
            Exercise(
                name: $0.name,
                primaryMuscleGroup: $0.muscle,
                secondaryMuscleGroups: $0.secondary,
                equipment: $0.equipment,
                measurementType: $0.measurement,
                searchAliases: $0.aliases,
                popularityRank: ExercisePopularity.rank(for: $0.name)
            )
        }
        exercises.forEach(context.insert)

        let didBackfillPopularity = backfillPopularity(for: existing)
        let didBackfillAliases = backfillSearchAliases(for: existing)
        if !exercises.isEmpty || didBackfillPopularity || didBackfillAliases { try context.save() }
        return exercises
    }

    /// Applies curated public-popularity ranks to any already-stored exercises that are
    /// still unranked (e.g. inserted before this field existed, or via catalog sync).
    @discardableResult
    static func backfillPopularity(for exercises: [Exercise]) -> Bool {
        var changed = false
        for exercise in exercises where exercise.popularityRank == ExercisePopularity.unrankedRank {
            guard let rank = ExercisePopularity.rank(forNormalizedName: exercise.normalizedName) else { continue }
            exercise.popularityRank = rank
            changed = true
        }
        return changed
    }

    /// Adds canonical search aliases to seeded exercises that predate alias support.
    @discardableResult
    static func backfillSearchAliases(for exercises: [Exercise]) -> Bool {
        var changed = false
        for exercise in exercises {
            guard let aliases = canonicalAliasesByNormalizedName[exercise.normalizedName] else { continue }
            let existing = Set(exercise.searchAliases.map(ExerciseNameNormalizer.normalize))
            let missing = aliases.filter { !existing.contains(ExerciseNameNormalizer.normalize($0)) }
            guard !missing.isEmpty else { continue }
            exercise.searchAliases.append(contentsOf: missing)
            changed = true
        }
        return changed
    }

    private static let canonicalAliasesByNormalizedName: [String: [String]] = [
        ExerciseNameNormalizer.normalize("Back Squat"): ["Squat"],
        ExerciseNameNormalizer.normalize("Triceps Pushdown"): ["Tricep Pushdown"],
    ]

    private static let seeds: [Seed] = [
        Seed("Barbell Bench Press", .chest, .barbell, secondary: [.triceps, .shoulders]),
        Seed("Incline Barbell Bench Press", .chest, .barbell, secondary: [.shoulders, .triceps]),
        Seed("Dumbbell Bench Press", .chest, .dumbbell, secondary: [.triceps, .shoulders]),
        Seed("Incline Dumbbell Press", .chest, .dumbbell, secondary: [.shoulders, .triceps]),
        Seed("Machine Chest Press", .chest, .machine, secondary: [.triceps]),
        Seed("Cable Fly", .chest, .cable),
        Seed("Push-Up", .chest, .bodyweight, .bodyweightAndRepetitions, secondary: [.triceps, .core]),
        Seed("Pull-Up", .back, .bodyweight, .bodyweightAndRepetitions, secondary: [.biceps]),
        Seed("Chin-Up", .back, .bodyweight, .bodyweightAndRepetitions, secondary: [.biceps]),
        Seed("Lat Pulldown", .back, .cable, secondary: [.biceps]),
        Seed("Barbell Row", .back, .barbell, secondary: [.biceps, .core]),
        Seed("One-Arm Dumbbell Row", .back, .dumbbell, secondary: [.biceps]),
        Seed("Seated Cable Row", .back, .cable, secondary: [.biceps]),
        Seed("Chest-Supported Row", .back, .machine, secondary: [.biceps]),
        Seed("Face Pull", .shoulders, .cable, secondary: [.back]),
        Seed("Barbell Overhead Press", .shoulders, .barbell, secondary: [.triceps, .core]),
        Seed("Dumbbell Shoulder Press", .shoulders, .dumbbell, secondary: [.triceps]),
        Seed("Machine Shoulder Press", .shoulders, .machine, secondary: [.triceps]),
        Seed("Dumbbell Lateral Raise", .shoulders, .dumbbell),
        Seed("Cable Lateral Raise", .shoulders, .cable),
        Seed("Reverse Pec Deck", .shoulders, .machine, secondary: [.back]),
        Seed("Barbell Curl", .biceps, .barbell),
        Seed("Dumbbell Curl", .biceps, .dumbbell),
        Seed("Hammer Curl", .biceps, .dumbbell, secondary: [.back]),
        Seed("Cable Curl", .biceps, .cable),
        Seed("Triceps Pushdown", .triceps, .cable, aliases: ["Tricep Pushdown"]),
        Seed("Overhead Triceps Extension", .triceps, .cable),
        Seed("Skull Crusher", .triceps, .barbell),
        Seed("Assisted Dip", .triceps, .machine, .assistedBodyweight, secondary: [.chest]),
        Seed("Back Squat", .quadriceps, .barbell, secondary: [.glutes, .hamstrings, .core], aliases: ["Squat"]),
        Seed("Front Squat", .quadriceps, .barbell, secondary: [.glutes, .core]),
        Seed("Leg Press", .quadriceps, .machine, secondary: [.glutes]),
        Seed("Leg Extension", .quadriceps, .machine),
        Seed("Bulgarian Split Squat", .quadriceps, .dumbbell, secondary: [.glutes]),
        Seed("Walking Lunge", .quadriceps, .dumbbell, secondary: [.glutes, .hamstrings]),
        Seed("Romanian Deadlift", .hamstrings, .barbell, secondary: [.glutes, .back]),
        Seed("Seated Leg Curl", .hamstrings, .machine),
        Seed("Lying Leg Curl", .hamstrings, .machine),
        Seed("Barbell Hip Thrust", .glutes, .barbell, secondary: [.hamstrings]),
        Seed("Cable Glute Kickback", .glutes, .cable),
        Seed("Standing Calf Raise", .calves, .machine),
        Seed("Seated Calf Raise", .calves, .machine),
        Seed("Plank", .core, .bodyweight, .duration),
        Seed("Hanging Leg Raise", .core, .bodyweight, .repetitionsOnly),
        Seed("Cable Crunch", .core, .cable),
        Seed("Ab Wheel Rollout", .core, .other, .repetitionsOnly),
        Seed("Deadlift", .fullBody, .barbell, secondary: [.back, .hamstrings, .glutes]),
        Seed("Sumo Deadlift", .fullBody, .barbell, secondary: [.glutes, .hamstrings, .quadriceps]),
        Seed("Kettlebell Swing", .fullBody, .kettlebell, secondary: [.glutes, .hamstrings]),
        Seed("Farmer Carry", .fullBody, .dumbbell, .distanceAndDuration, secondary: [.core]),
        Seed("Goblet Squat", .quadriceps, .kettlebell, secondary: [.glutes, .core]),
        Seed("Smith Machine Squat", .quadriceps, .smithMachine, secondary: [.glutes]),
        Seed("Smith Machine Bench Press", .chest, .smithMachine, secondary: [.triceps]),
        Seed("Dip", .chest, .bodyweight, .bodyweightAndRepetitions, secondary: [.triceps]),
        Seed("Weighted Pull-Up", .back, .bodyweight, .bodyweightPlusAddedWeight, secondary: [.biceps])
    ]
}
