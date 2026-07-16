import Foundation

/// Hand-verified AscendAPI media links for curated seed exercises whose display
/// names do not fuzzy-match reliably (or have no close catalog entry at all).
enum ExerciseSeedMediaOverrides {
    struct Override: Sendable, Equatable {
        let catalogExerciseID: String
        let mediaURLString: String
        let enrichSearchQueries: [String]
        /// When true, the override is a closest-available proxy rather than a true match.
        let isProxy: Bool
    }

    static func override(for exercise: Exercise) -> Override? {
        overridesByNormalizedName[exercise.normalizedName]
    }

    static func override(forNormalizedName normalizedName: String) -> Override? {
        overridesByNormalizedName[normalizedName]
    }

    static var allNormalizedNames: Set<String> {
        Set(overridesByNormalizedName.keys)
    }

    static var allOverrides: [Override] {
        Array(overridesByNormalizedName.values)
    }

    static func normalizedSeedName(forCatalogExerciseID id: String) -> String? {
        normalizedSeedNameByCatalogID[id]
    }

    static func hasKnownInvalidMediaAssignment(for exercise: Exercise) -> Bool {
        guard let invalidIDs = invalidCatalogExerciseIDsByNormalizedName[
            ExerciseNameNormalizer.normalize(exercise.name)
        ] else { return false }

        if let externalID = exercise.externalCatalogID,
           invalidIDs.contains(externalID) {
            return true
        }
        guard let mediaURLString = exercise.mediaURLString,
              let filename = URL(string: mediaURLString)?.deletingPathExtension().lastPathComponent
        else { return false }
        return invalidIDs.contains(filename)
    }

    private static let overridesByNormalizedName: [String: Override] = {
        func entry(
            _ name: String,
            id: String,
            queries: [String],
            proxy: Bool = false
        ) -> (String, Override) {
            let key = ExerciseNameNormalizer.normalize(name)
            let override = Override(
                catalogExerciseID: id,
                mediaURLString: "https://static.exercisedb.dev/media/\(id).gif",
                enrichSearchQueries: queries,
                isProxy: proxy
            )
            return (key, override)
        }

        return Dictionary(
            uniqueKeysWithValues: [
                entry("Ab Wheel Rollout", id: "NAgVB3t", queries: ["ab wheel", "wheel rollerout", "ab roller"]),
                entry("Farmer Carry", id: "qPEzJjA", queries: ["farmer walk", "farmers walk"]),
                entry("Back Squat", id: "DhMl549", queries: ["barbell full squat", "back squat", "squat"], proxy: true),
                entry("Barbell Row", id: "eZyBC3j", queries: ["barbell bent over row", "bent over row"]),
                entry("Barbell Overhead Press", id: "kTbSH9h", queries: ["barbell seated overhead press", "military press"], proxy: true),
                entry("Deadlift", id: "ila4NZS", queries: ["barbell deadlift", "deadlift"]),
                entry("Front Squat", id: "qi996YS", queries: ["barbell clean-grip front squat", "front squat"]),
                entry("Cable Fly", id: "FVmZVhk", queries: ["cable low fly", "cable fly"]),
                entry("Machine Chest Press", id: "DOoWcnA", queries: ["lever chest press", "machine chest press"]),
                entry("Machine Shoulder Press", id: "67n3r98", queries: ["lever shoulder press", "machine shoulder press"]),
                entry("Dumbbell Curl", id: "3s4NnTh", queries: ["dumbbell standing biceps curl", "dumbbell curl"]),
                entry("Plank", id: "VBAWRPG", queries: ["front plank", "plank"], proxy: true),
                entry("Cable Crunch", id: "WW95auq", queries: ["cable kneeling crunch", "cable crunch"]),
                entry("Assisted Dip", id: "PAgTVaK", queries: ["assisted chest dip", "assisted dip"]),
                entry("Reverse Pec Deck", id: "myfUsKf", queries: ["reverse fly", "rear delt fly", "pec deck"]),
                entry("Cable Glute Kickback", id: "HEJ6DIX", queries: ["cable kickback", "glute kickback"]),
                entry("Smith Machine Squat", id: "NNoHCEA", queries: ["smith full squat", "smith squat"], proxy: true),
                entry("Barbell Bench Press", id: "EIeI8Vf", queries: ["barbell bench press"]),
                entry("Incline Barbell Bench Press", id: "3TZduzM", queries: ["barbell incline bench press"]),
                entry("Dumbbell Bench Press", id: "SpYC0Kp", queries: ["dumbbell bench press"]),
                entry("Push-Up", id: "I4hDWkc", queries: ["push-up", "push up"]),
                entry("Pull-Up", id: "lBDjFxJ", queries: ["pull-up", "pull up"]),
                entry("Chin-Up", id: "T2mxWqc", queries: ["chin-up", "chin up"]),
                entry("Lat Pulldown", id: "LEprlgG", queries: ["lat pulldown", "cable lat pulldown"]),
                entry("Dumbbell Bent-Over Row", id: "BJ0Hz5L", queries: ["dumbbell bent over row", "two dumbbell row"]),
                entry("Romanian Deadlift", id: "o6LqKKP", queries: ["romanian deadlift", "barbell romanian deadlift"]),
                entry("Leg Press", id: "V07qpXy", queries: ["leg press", "lever leg press"]),
                entry("Leg Extension", id: "my33uHU", queries: ["leg extension", "lever leg extension"]),
                entry("Lying Leg Curl", id: "17lJ1kr", queries: ["lying leg curl", "lever lying leg curl"]),
                entry("Seated Leg Curl", id: "Zg3XY7P", queries: ["seated leg curl", "lever seated leg curl"]),
                entry("Dumbbell Lateral Raise", id: "DsgkuIt", queries: ["dumbbell lateral raise"]),
                entry("Cable Lateral Raise", id: "goJ6ezq", queries: ["cable lateral raise"]),
                entry("Barbell Curl", id: "25GPyDY", queries: ["barbell curl", "barbell biceps curl"]),
                entry("Cable Curl", id: "G08RZcQ", queries: ["cable curl", "cable biceps curl", "straight bar cable curl"]),
                entry("Hammer Curl", id: "2NpxjC1", queries: ["dumbbell hammer curl"]),
                entry("Triceps Pushdown", id: "9tvVVM9", queries: ["triceps pushdown", "cable triceps pushdown"]),
                entry("Overhead Triceps Extension", id: "2IxROQ1", queries: ["overhead triceps extension", "cable overhead triceps extension"]),
                entry("Skull Crusher", id: "h8LFzo9", queries: ["skull crusher", "lying triceps extension"]),
                entry("Sumo Deadlift", id: "KgI0tqW", queries: ["sumo deadlift", "barbell sumo deadlift"]),
                entry("Walking Lunge", id: "IZVHb27", queries: ["walking lunge"], proxy: true),
                entry("Goblet Squat", id: "ZA8b5hc", queries: ["goblet squat", "kettlebell goblet squat"]),
                entry("One-Arm Dumbbell Row", id: "C0MA9bC", queries: ["dumbbell one arm bent-over row", "one arm row"]),
                entry("Seated Cable Row", id: "A3P4O0R", queries: ["cable seated row", "seated row"]),
                entry("Dip", id: "9WTm7dq", queries: ["chest dip", "dip"]),
                entry("Standing Calf Raise", id: "6HmFgmx", queries: ["standing calf raise"]),
                entry("Seated Calf Raise", id: "bOOdeyc", queries: ["seated calf raise", "lever seated calf raise"]),
                entry("Hanging Leg Raise", id: "I3tsCnC", queries: ["hanging leg raise"]),
                entry("Kettlebell Swing", id: "UHJlbu3", queries: ["kettlebell swing"]),
                entry("Weighted Pull-Up", id: "HMzLjXx", queries: ["weighted pull-up", "weighted pull up"]),
            ]
        )
    }()

    private static let normalizedSeedNameByCatalogID: [String: String] = Dictionary(
        uniqueKeysWithValues: overridesByNormalizedName.map { normalizedName, override in
            (override.catalogExerciseID, normalizedName)
        }
    )

    private static let invalidCatalogExerciseIDsByNormalizedName: [String: Set<String>] = [
        ExerciseNameNormalizer.normalize("Deadlift"): ["GUT8I22"],
        ExerciseNameNormalizer.normalize("Face Pull"): ["G61cXLk"],
        ExerciseNameNormalizer.normalize("Barbell Hip Thrust"): ["qKBpF7I"],
        ExerciseNameNormalizer.normalize("Dumbbell Shoulder Press"): ["Xy4jlWA"],
        ExerciseNameNormalizer.normalize("Bulgarian Split Squat"): ["HBYyX94"],
        ExerciseNameNormalizer.normalize("Incline Dumbbell Press"): ["bfiHMpI"],
    ]
}
