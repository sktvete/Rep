import Foundation

/// Resolves exercise artwork without depending on the retired ExerciseDB service.
///
/// The bundled catalog is sourced from Free Exercise DB under the Unlicense. Its
/// revision is pinned so a catalog ID always resolves to stable artwork instead of
/// whatever happens to be on the repository's default branch later.
enum ExerciseCatalogMedia {
    static let freeExerciseDBRevision = "b0eed061e1c832b3ed815fbaa4b45b3cdc14df49"

    private static let bundledIDPrefix = "rep:free-exercise-db:"
    private static let rawGitHubHost = "raw.githubusercontent.com"

    /// Returns the best display URL for an exercise. Bundled and curated exercises
    /// prefer the pinned Free Exercise DB still. YouTube frames are only used when
    /// no catalog thumbnail exists. Custom media remains supported; retired
    /// ExerciseDB URLs are ignored.
    static func resolvedURL(for exercise: Exercise) -> URL? {
        if exercise.isCustom, let customURL = safeStoredMediaURL(for: exercise) {
            return customURL
        }

        if let sourceID = sourceID(for: exercise) {
            return pinnedThumbnailURL(sourceID: sourceID)
        }

        if let videoID = exercise.helpYouTubeVideoID,
           let youtubeThumbnail = ExerciseHelpVideoCatalog.thumbnailURL(forVideoID: videoID) {
            return youtubeThumbnail
        }

        return safeStoredMediaURL(for: exercise)
    }

    static func pinnedThumbnailURL(for exercise: Exercise) -> URL? {
        sourceID(for: exercise).flatMap { pinnedThumbnailURL(sourceID: $0) }
    }

    static func pinnedThumbnailURL(sourceID: String) -> URL? {
        guard isSafeSourceID(sourceID) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = rawGitHubHost
        components.path = "/yuhonas/free-exercise-db/\(freeExerciseDBRevision)/exercises/\(sourceID)/0.jpg"
        return components.url
    }

    static func sourceID(for exercise: Exercise) -> String? {
        if let bundledID = exercise.bundledCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines),
           bundledID.hasPrefix(bundledIDPrefix) {
            let sourceID = String(bundledID.dropFirst(bundledIDPrefix.count))
            if isSafeSourceID(sourceID) { return sourceID }
        }

        guard !exercise.isCustom else { return nil }
        return sourceIDByCanonicalName[ExerciseNameNormalizer.normalize(exercise.name)]
    }

    private static func safeStoredMediaURL(for exercise: Exercise) -> URL? {
        guard let value = exercise.mediaURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              !isRetiredExerciseDBURL(url)
        else { return nil }
        return url
    }

    private static func isRetiredExerciseDBURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "exercisedb.dev"
            || host.hasSuffix(".exercisedb.dev")
            || host == "ascendapi.com"
            || host.hasSuffix(".ascendapi.com")
    }

    private static func isSafeSourceID(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-()'."))
        return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Curated Rep names intentionally stay friendly and concise. These aliases map
    /// the common names to the closest exact source directory when the upstream title
    /// differs, so popular starter exercises still receive stable artwork.
    private static let sourceIDByCanonicalName: [String: String] = {
        let aliases: [(String, String)] = [
            ("Barbell Bench Press", "Barbell_Bench_Press_-_Medium_Grip"),
            ("Incline Barbell Bench Press", "Barbell_Incline_Bench_Press_-_Medium_Grip"),
            ("Machine Chest Press", "Leverage_Chest_Press"),
            ("Cable Fly", "Flat_Bench_Cable_Flyes"),
            ("Push-Up", "Pushups"),
            ("Pull-Up", "Pullups"),
            ("Lat Pulldown", "Wide-Grip_Lat_Pulldown"),
            ("Barbell Row", "Bent_Over_Barbell_Row"),
            ("Bent Over Row", "Bent_Over_Barbell_Row"),
            ("Dumbbell Bent-Over Row", "Bent_Over_Two-Dumbbell_Row"),
            ("One-Arm Dumbbell Row", "One-Arm_Dumbbell_Row"),
            ("Seated Cable Row", "Seated_Cable_Rows"),
            ("Chest-Supported Row", "Dumbbell_Incline_Row"),
            ("Barbell Overhead Press", "Standing_Military_Press"),
            ("Overhead Press", "Standing_Military_Press"),
            ("Dumbbell Curl", "Dumbbell_Bicep_Curl"),
            ("Cable Curl", "Standing_Biceps_Cable_Curl"),
            ("Rope Biceps Curl", "Cable_Hammer_Curls_-_Rope_Attachment"),
            ("Hammer Curl", "Hammer_Curls"),
            ("Dumbbell Lateral Raise", "Side_Lateral_Raise"),
            ("Cable Lateral Raise", "Cable_Seated_Lateral_Raise"),
            ("Reverse Pec Deck", "Reverse_Machine_Flyes"),
            ("Overhead Triceps Extension", "Cable_Rope_Overhead_Triceps_Extension"),
            ("Skull Crusher", "EZ-Bar_Skullcrusher"),
            ("Assisted Dip", "Dip_Machine"),
            ("Squat", "Barbell_Full_Squat"),
            ("Back Squat", "Barbell_Full_Squat"),
            ("Front Squat", "Front_Barbell_Squat"),
            ("Leg Extension", "Leg_Extensions"),
            ("Bulgarian Split Squat", "Split_Squat_with_Dumbbells"),
            ("Walking Lunge", "Dumbbell_Lunges"),
            ("Lying Leg Curl", "Lying_Leg_Curls"),
            ("Standing Calf Raise", "Standing_Calf_Raises"),
            ("Ab Wheel Rollout", "Ab_Roller"),
            ("Deadlift", "Barbell_Deadlift"),
            ("Farmer Carry", "Farmers_Walk"),
            ("Dip", "Dips_-_Chest_Version"),
            ("Weighted Pull-Up", "Weighted_Pull_Ups")
        ]

        return Dictionary(uniqueKeysWithValues: aliases.map {
            (ExerciseNameNormalizer.normalize($0.0), $0.1)
        })
    }()
}
