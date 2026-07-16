import Foundation

/// A curated, offline ranking of broadly popular strength exercises.
///
/// The bundled catalog exposes no popularity signal, so "public popularity" is expressed as a
/// hand-ordered list of the movements most people log. The first entry is the most
/// popular. Anything not on the list sorts after ranked exercises via ``unrankedRank``.
enum ExercisePopularity {
    /// Sentinel rank for exercises with no curated popularity. Kept well above any real
    /// rank so unranked movements always fall after ranked ones.
    static let unrankedRank = 1_000_000

    /// Returns the curated rank for a normalized exercise name, or `nil` when unranked.
    static func rank(forNormalizedName normalizedName: String) -> Int? {
        rankByNormalizedName[normalizedName]
    }

    /// Returns the curated rank for a display name, or ``unrankedRank`` when unranked.
    static func rank(for name: String) -> Int {
        rank(forNormalizedName: ExerciseNameNormalizer.normalize(name)) ?? unrankedRank
    }

    private static let rankByNormalizedName: [String: Int] = {
        var map: [String: Int] = [:]
        for (index, name) in orderedNames.enumerated() {
            let key = ExerciseNameNormalizer.normalize(name)
            if map[key] == nil { map[key] = index }
        }
        return map
    }()

    /// Ordered most-popular first. Aliases for common naming variants are included so
    /// catalog rows that differ only in phrasing still inherit a rank.
    private static let orderedNames: [String] = [
        "Barbell Bench Press",
        "Squat",
        "Back Squat",
        "Deadlift",
        "Pull-Up",
        "Push-Up",
        "Barbell Overhead Press",
        "Overhead Press",
        "Barbell Row",
        "Bent Over Row",
        "Lat Pulldown",
        "Dumbbell Bench Press",
        "Incline Barbell Bench Press",
        "Incline Dumbbell Press",
        "Romanian Deadlift",
        "Leg Press",
        "Dumbbell Shoulder Press",
        "Barbell Curl",
        "Dumbbell Curl",
        "Triceps Pushdown",
        "Tricep Pushdown",
        "Dumbbell Lateral Raise",
        "Seated Cable Row",
        "Leg Extension",
        "Lying Leg Curl",
        "Seated Leg Curl",
        "Front Squat",
        "Hammer Curl",
        "Chin-Up",
        "Dip",
        "Face Pull",
        "Barbell Hip Thrust",
        "Hip Thrust",
        "Goblet Squat",
        "Bulgarian Split Squat",
        "Walking Lunge",
        "Lunge",
        "Cable Fly",
        "Machine Chest Press",
        "Machine Shoulder Press",
        "Skull Crusher",
        "Overhead Triceps Extension",
        "Cable Curl",
        "Standing Calf Raise",
        "Seated Calf Raise",
        "Plank",
        "Hanging Leg Raise",
        "Cable Crunch",
        "Sumo Deadlift",
        "Kettlebell Swing",
        "One-Arm Dumbbell Row",
        "Reverse Pec Deck",
        "Cable Lateral Raise",
        "Cable Glute Kickback",
        "Farmer Carry",
        "Ab Wheel Rollout",
        "Weighted Pull-Up",
        "Smith Machine Squat",
        "Assisted Dip"
    ]
}
