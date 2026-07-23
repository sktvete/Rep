import Foundation

enum GuidedRoutineFocus: String, CaseIterable, Identifiable, Hashable {
    case legs
    case push
    case pull
    case core

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .legs: "figure.strengthtraining.traditional"
        case .push: "arrow.up.forward.circle.fill"
        case .pull: "arrow.down.backward.circle.fill"
        case .core: "figure.core.training"
        }
    }

    var summary: String {
        switch self {
        case .legs: "Quads, hamstrings, glutes and calves"
        case .push: "Chest, shoulders and triceps"
        case .pull: "Back, rear shoulders and biceps"
        case .core: "Stability, rotation and trunk strength"
        }
    }
}

enum GuidedRoutineExperience: String, CaseIterable, Identifiable, Hashable {
    case beginner
    case intermediate
    case expert

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    private var progression: Int {
        switch self {
        case .beginner: 0
        case .intermediate: 1
        case .expert: 2
        }
    }

    func meets(_ minimum: GuidedRoutineExperience) -> Bool {
        progression >= minimum.progression
    }
}

enum GuidedRoutineEquipmentProfile: String, CaseIterable, Identifiable, Hashable {
    case fullGym
    case dumbbells
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullGym: "Full gym"
        case .dumbbells: "Dumbbells"
        case .minimal: "Minimal"
        }
    }

    var systemImage: String {
        switch self {
        case .fullGym: "building.2"
        case .dumbbells: "dumbbell.fill"
        case .minimal: "figure.strengthtraining.functional"
        }
    }

    func accepts(_ equipment: Equipment) -> Bool {
        switch self {
        case .fullGym:
            true
        case .dumbbells:
            [.dumbbell, .kettlebell, .bodyweight, .other].contains(equipment)
        case .minimal:
            [.bodyweight, .other].contains(equipment)
        }
    }
}

enum GuidedRoutineDuration: String, CaseIterable, Identifiable, Hashable {
    case quick
    case standard
    case extended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: "40–45 min"
        case .standard: "50–60 min"
        case .extended: "65–75 min"
        }
    }

    var setAdjustment: Int {
        switch self {
        case .quick: -1
        case .standard: 0
        case .extended: 1
        }
    }

    var estimatedMinutes: Int {
        switch self {
        case .quick: 43
        case .standard: 55
        case .extended: 70
        }
    }
}

struct GuidedExerciseCandidateDefinition: Hashable {
    let id: String
    let preferredNames: [String]
    let reason: String
    let equipmentProfiles: Set<GuidedRoutineEquipmentProfile>
    let beginnerRank: Int
    let intermediateRank: Int
    let expertRank: Int
    let minimumExperience: GuidedRoutineExperience

    init(
        _ name: String,
        aliases: [String] = [],
        reason: String,
        profiles: Set<GuidedRoutineEquipmentProfile>,
        newRank: Int,
        experiencedRank: Int,
        intermediateRank: Int? = nil,
        minimumExperience: GuidedRoutineExperience = .beginner
    ) {
        id = ExerciseNameNormalizer.normalize(name)
        preferredNames = [name] + aliases
        self.reason = reason
        equipmentProfiles = profiles
        beginnerRank = newRank
        expertRank = experiencedRank
        self.intermediateRank = intermediateRank ?? (newRank + experiencedRank) / 2
        self.minimumExperience = minimumExperience
    }

    func rank(for experience: GuidedRoutineExperience) -> Int {
        switch experience {
        case .beginner: beginnerRank
        case .intermediate: intermediateRank
        case .expert: expertRank
        }
    }

    func isAvailable(to experience: GuidedRoutineExperience) -> Bool {
        experience.meets(minimumExperience)
    }

    func supports(_ profile: GuidedRoutineEquipmentProfile) -> Bool {
        profile == .fullGym || equipmentProfiles.contains(profile)
    }
}

struct GuidedMovementSlot: Identifiable, Hashable {
    let id: String
    let title: String
    let purpose: String
    let fallbackMuscle: MuscleGroup
    let setCount: Int
    let repetitions: Int
    let restSeconds: Int
    let candidates: [GuidedExerciseCandidateDefinition]

    func setCount(for duration: GuidedRoutineDuration) -> Int {
        max(2, setCount + duration.setAdjustment)
    }
}

struct GuidedRoutineTemplate: Identifiable, Hashable {
    let focus: GuidedRoutineFocus
    let slots: [GuidedMovementSlot]

    var id: GuidedRoutineFocus { focus }
    var defaultName: String { focus.title }
}

struct GuidedResolvedExerciseOption: Identifiable {
    let candidateID: String
    let exercise: Exercise
    let reason: String
    let isRecommended: Bool

    var id: UUID { exercise.id }
}

struct GuidedRoutineSelection: Identifiable {
    let slot: GuidedMovementSlot
    var exercise: Exercise

    var id: String { slot.id }
}

enum GuidedRoutineBuilderError: LocalizedError {
    case incompleteSlot(String)

    var errorDescription: String? {
        switch self {
        case .incompleteSlot(let title):
            "Rep couldn’t find three suitable exercises for \(title)."
        }
    }
}

enum GuidedRoutineCatalog {
    static let templates: [GuidedRoutineTemplate] = [
        GuidedRoutineTemplate(focus: .legs, slots: legs),
        GuidedRoutineTemplate(focus: .push, slots: push),
        GuidedRoutineTemplate(focus: .pull, slots: pull),
        GuidedRoutineTemplate(focus: .core, slots: core)
    ]

    static func template(for focus: GuidedRoutineFocus) -> GuidedRoutineTemplate {
        templates.first { $0.focus == focus }!
    }

    private static let dumbbellOrMinimal: Set<GuidedRoutineEquipmentProfile> = [.dumbbells, .minimal]
    private static let dumbbellOnly: Set<GuidedRoutineEquipmentProfile> = [.dumbbells]
    private static let minimalOnly: Set<GuidedRoutineEquipmentProfile> = [.minimal]

    private static let legs: [GuidedMovementSlot] = [
        slot(
            "legs-squat",
            "Squat movement",
            "Build the quads and glutes with a stable knee-dominant movement.",
            muscle: .quadriceps,
            sets: 3,
            reps: 8,
            rest: 150,
            candidates: [
                candidate("Back Squat", aliases: ["Squat", "Barbell Squat", "Barbell Full Squat"], reason: "The classic lower-body strength staple", new: 2, experienced: 0),
                candidate("Hack Squat", reason: "Stable and easy to learn", new: 0, experienced: 2),
                candidate("Goblet Squat", reason: "Simple and confidence-building", profiles: dumbbellOnly, new: 1, experienced: 3),
                candidate("Dumbbell Squat", reason: "Flexible dumbbell option", profiles: dumbbellOnly, new: 2, experienced: 1),
                candidate("Bodyweight Squat", reason: "No equipment needed", profiles: dumbbellOrMinimal, new: 0, experienced: 5),
                candidate("Chair Squat", reason: "Supported beginner option", new: 1, experienced: 6),
                candidate("Split Squats", reason: "Challenging without heavy equipment", profiles: minimalOnly, new: 3, experienced: 2)
            ]
        ),
        slot(
            "legs-hinge",
            "Hip hinge",
            "Train the hamstrings and glutes through a strong hip-driven pattern.",
            muscle: .hamstrings,
            sets: 3,
            reps: 10,
            rest: 120,
            candidates: [
                candidate("Romanian Deadlift", reason: "Easy to load and progress", new: 3, experienced: 0),
                candidate("Stiff-Legged Dumbbell Deadlift", reason: "Approachable dumbbell hinge", profiles: dumbbellOnly, new: 0, experienced: 1),
                candidate("Pull Through", reason: "Smooth cable resistance", new: 1, experienced: 3),
                candidate("Hyperextensions (Back Extensions)", reason: "Supported posterior-chain work", profiles: dumbbellOrMinimal, new: 0, experienced: 2),
                candidate("Band Good Morning (Pull Through)", reason: "Compact minimal-equipment option", profiles: minimalOnly, new: 1, experienced: 4),
                candidate("Single Leg Glute Bridge", reason: "Bodyweight glute focus", profiles: minimalOnly, new: 2, experienced: 3)
            ]
        ),
        slot(
            "legs-unilateral",
            "Single-leg strength",
            "Build balanced strength one leg at a time.",
            muscle: .quadriceps,
            sets: 3,
            reps: 10,
            rest: 90,
            candidates: [
                candidate("Walking Lunge", aliases: ["Dumbbell Rear Lunge"], reason: "A familiar single-leg staple", profiles: dumbbellOnly, new: 0, experienced: 1),
                candidate("Bulgarian Split Squat", aliases: ["Split Squat with Dumbbells"], reason: "Easy to load and progress", profiles: dumbbellOnly, new: 2, experienced: 0),
                candidate("Smith Single-Leg Split Squat", reason: "Guided machine stability", new: 0, experienced: 2),
                candidate("Bodyweight Walking Lunge", reason: "No equipment needed", profiles: dumbbellOrMinimal, new: 2, experienced: 3),
                candidate("Step-up with Knee Raise", reason: "Practical single-leg control", profiles: dumbbellOrMinimal, new: 1, experienced: 2),
                candidate("Split Squats", reason: "Strong bodyweight progression", profiles: minimalOnly, new: 0, experienced: 1)
            ]
        ),
        slot(
            "legs-curl",
            "Hamstring curl",
            "Train knee flexion to complement the hip hinge.",
            muscle: .hamstrings,
            sets: 3,
            reps: 12,
            rest: 75,
            candidates: [
                candidate("Seated Leg Curl", reason: "Stable full-range machine", new: 0, experienced: 0),
                candidate("Lying Leg Curl", aliases: ["Lying Leg Curls"], reason: "Common machine alternative", new: 1, experienced: 1),
                candidate("Standing Leg Curl", reason: "Useful single-leg option", new: 2, experienced: 2),
                candidate("Ball Leg Curl", reason: "Home-friendly stability challenge", profiles: dumbbellOrMinimal, new: 0, experienced: 1),
                candidate("Seated Band Hamstring Curl", reason: "Minimal-equipment curl", profiles: minimalOnly, new: 1, experienced: 0),
                candidate("Single Leg Glute Bridge", reason: "Bodyweight fallback", profiles: minimalOnly, new: 2, experienced: 2)
            ]
        ),
        slot(
            "legs-calves",
            "Calves",
            "Finish with controlled ankle strength through a full range.",
            muscle: .calves,
            sets: 3,
            reps: 15,
            rest: 60,
            candidates: [
                candidate("Standing Calf Raise", aliases: ["Standing Calf Raises"], reason: "Simple standing machine", new: 0, experienced: 1),
                candidate("Seated Calf Raise", reason: "Stable seated variation", new: 1, experienced: 0),
                candidate("Calf Press On The Leg Press Machine", reason: "Easy to load heavily", new: 2, experienced: 2),
                candidate("Standing Dumbbell Calf Raise", reason: "Straightforward dumbbell option", profiles: dumbbellOnly, new: 0, experienced: 0),
                candidate("Calf Raise On A Dumbbell", reason: "Minimal setup", profiles: dumbbellOrMinimal, new: 1, experienced: 1),
                candidate("Calf Raises - With Bands", reason: "Portable band resistance", profiles: minimalOnly, new: 0, experienced: 0)
            ]
        )
    ]

    private static let push: [GuidedMovementSlot] = [
        slot(
            "push-horizontal",
            "Horizontal press",
            "Use your chest, shoulders and triceps in the main press.",
            muscle: .chest,
            sets: 3,
            reps: 8,
            rest: 150,
            candidates: [
                candidate("Barbell Bench Press", aliases: ["Barbell Bench Press - Medium Grip"], reason: "The standard chest strength staple", new: 2, experienced: 0),
                candidate("Dumbbell Bench Press", reason: "Natural range with dumbbells", profiles: dumbbellOnly, new: 1, experienced: 1),
                candidate("Machine Chest Press", aliases: ["Machine Bench Press"], reason: "Stable and easy to learn", new: 0, experienced: 3),
                candidate("Push-Up", aliases: ["Push-Up Wide"], reason: "Reliable bodyweight press", profiles: dumbbellOrMinimal, new: 1, experienced: 2),
                candidate("Incline Push-Up Medium", reason: "Beginner-friendly bodyweight press", profiles: minimalOnly, new: 0, experienced: 4),
                candidate("Suspended Push-Up", reason: "Advanced minimal-equipment press", profiles: minimalOnly, minimum: .intermediate, new: 3, experienced: 1)
            ]
        ),
        slot(
            "push-vertical",
            "Overhead press",
            "Build shoulder and triceps strength overhead.",
            muscle: .shoulders,
            sets: 3,
            reps: 10,
            rest: 120,
            candidates: [
                candidate("Barbell Overhead Press", aliases: ["Barbell Shoulder Press"], reason: "The standard overhead strength staple", new: 2, experienced: 0),
                candidate("Machine Shoulder Press", aliases: ["Leverage Shoulder Press"], reason: "Stable shoulder press", new: 0, experienced: 2),
                candidate("Dumbbell Shoulder Press", reason: "Flexible and easy to adjust", profiles: dumbbellOnly, new: 1, experienced: 1),
                candidate("Dumbbell One-Arm Shoulder Press", reason: "Single-arm control", profiles: dumbbellOnly, new: 2, experienced: 0),
                candidate("Shoulder Press - With Bands", reason: "Portable overhead resistance", profiles: minimalOnly, new: 0, experienced: 2),
                candidate("Handstand Push-Ups", reason: "Advanced bodyweight option", profiles: minimalOnly, minimum: .expert, new: 5, experienced: 0)
            ]
        ),
        slot(
            "push-incline",
            "Upper-chest press",
            "Add a second press from an incline angle.",
            muscle: .chest,
            sets: 3,
            reps: 10,
            rest: 90,
            candidates: [
                candidate("Incline Barbell Bench Press", aliases: ["Barbell Incline Bench Press - Medium Grip"], reason: "The standard upper-chest press", new: 3, experienced: 0),
                candidate("Leverage Incline Chest Press", reason: "Stable incline machine", new: 0, experienced: 2),
                candidate("Incline Dumbbell Press", reason: "Balanced upper-chest option", profiles: dumbbellOnly, new: 1, experienced: 0),
                candidate("Incline Cable Chest Press", reason: "Smooth resistance throughout", new: 2, experienced: 3),
                candidate("Push-Ups With Feet Elevated", reason: "Upper-chest bodyweight challenge", profiles: dumbbellOrMinimal, minimum: .intermediate, new: 2, experienced: 0),
                candidate("Incline Push-Up Medium", reason: "Easy bodyweight alternative", profiles: minimalOnly, new: 0, experienced: 4)
            ]
        ),
        slot(
            "push-lateral",
            "Side shoulders",
            "Train shoulder width with a controlled lateral raise.",
            muscle: .shoulders,
            sets: 3,
            reps: 15,
            rest: 60,
            candidates: [
                candidate("Dumbbell Lateral Raise", aliases: ["Side Lateral Raise"], reason: "The classic shoulder-width staple", profiles: dumbbellOnly, new: 1, experienced: 1),
                candidate("Cable Lateral Raise", aliases: ["Cable Seated Lateral Raise"], reason: "Smooth cable tension", new: 0, experienced: 0),
                candidate("Seated Side Lateral Raise", reason: "Stable seated dumbbell option", profiles: dumbbellOnly, new: 0, experienced: 2),
                candidate("One-Arm Incline Lateral Raise", reason: "Long-range shoulder challenge", profiles: dumbbellOnly, new: 3, experienced: 0),
                candidate("Lateral Raise - With Bands", reason: "Portable band option", profiles: minimalOnly, new: 0, experienced: 0),
                candidate("Lying One-Arm Lateral Raise", reason: "Controlled minimal-load variation", profiles: dumbbellOnly, new: 2, experienced: 3)
            ]
        ),
        slot(
            "push-triceps",
            "Triceps",
            "Finish the elbow extensors after pressing.",
            muscle: .triceps,
            sets: 3,
            reps: 12,
            rest: 75,
            candidates: [
                candidate("Triceps Pushdown", reason: "The standard cable triceps staple", new: 0, experienced: 0),
                candidate("Triceps Pushdown - Rope Attachment", reason: "Comfortable rope variation", new: 1, experienced: 1),
                candidate("Cable Rope Overhead Triceps Extension", reason: "Overhead long-head focus", new: 2, experienced: 1),
                candidate("Standing One-Arm Dumbbell Triceps Extension", reason: "Single dumbbell setup", profiles: dumbbellOnly, new: 1, experienced: 0),
                candidate("Push-Ups - Close Triceps Position", reason: "No equipment needed", profiles: dumbbellOrMinimal, new: 0, experienced: 1),
                candidate("Close-Grip Push-Up off of a Dumbbell", reason: "Compact close-grip option", profiles: dumbbellOrMinimal, new: 2, experienced: 2)
            ]
        )
    ]

    private static let pull: [GuidedMovementSlot] = [
        slot(
            "pull-vertical",
            "Vertical pull",
            "Build the lats with a pull from overhead.",
            muscle: .back,
            sets: 3,
            reps: 10,
            rest: 120,
            candidates: [
                candidate("Lat Pulldown", aliases: ["Full Range-Of-Motion Lat Pulldown"], reason: "The standard scalable back staple", new: 0, experienced: 2),
                candidate("Close-Grip Front Lat Pulldown", reason: "Comfortable close-grip pull", new: 1, experienced: 3),
                candidate("Band Assisted Pull-Up", reason: "Build toward pull-ups", profiles: minimalOnly, new: 0, experienced: 2),
                candidate("Chin-Up", reason: "Strong bodyweight progression", profiles: dumbbellOrMinimal, minimum: .intermediate, new: 3, experienced: 0),
                candidate("Wide-Grip Rear Pull-Up", reason: "Advanced bodyweight pull", profiles: minimalOnly, minimum: .expert, new: 5, experienced: 1),
                candidate("Underhand Cable Pulldowns", reason: "Biceps-friendly cable pull", new: 2, experienced: 1)
            ]
        ),
        slot(
            "pull-horizontal",
            "Horizontal row",
            "Train the mid-back with a controlled row.",
            muscle: .back,
            sets: 3,
            reps: 10,
            rest: 120,
            candidates: [
                candidate("Barbell Row", reason: "The classic free-weight back staple", new: 3, experienced: 0),
                candidate("Seated Cable Row", aliases: ["Seated Cable Rows"], reason: "Stable and easy to learn", new: 0, experienced: 2),
                candidate("Dumbbell Incline Row", reason: "Chest-supported dumbbell row", profiles: dumbbellOnly, new: 1, experienced: 0),
                candidate("One-Arm Dumbbell Row", reason: "Common single-arm option", profiles: dumbbellOnly, new: 2, experienced: 1),
                candidate("T-Bar Row with Handle", reason: "Heavy supported progression", new: 4, experienced: 0),
                candidate("Inverted Row", reason: "Scalable bodyweight row", profiles: dumbbellOrMinimal, new: 1, experienced: 1),
                candidate("Suspended Row", reason: "Portable bodyweight row", profiles: minimalOnly, new: 0, experienced: 2)
            ]
        ),
        slot(
            "pull-rear-delts",
            "Rear shoulders",
            "Balance pressing with rear-delt and upper-back work.",
            muscle: .shoulders,
            sets: 3,
            reps: 15,
            rest: 75,
            candidates: [
                candidate("Face Pull", reason: "Shoulder-friendly cable pull", new: 0, experienced: 0),
                candidate("Cable Rear Delt Fly", reason: "Smooth rear-delt tension", new: 1, experienced: 1),
                candidate("Dumbbell Lying Rear Lateral Raise", reason: "Supported dumbbell option", profiles: dumbbellOnly, new: 0, experienced: 0),
                candidate("Seated Bent-Over Rear Delt Raise", reason: "Simple seated variation", profiles: dumbbellOnly, new: 1, experienced: 2),
                candidate("Lying Rear Delt Raise", reason: "Minimal-load rear-delt work", profiles: dumbbellOnly, new: 2, experienced: 1),
                candidate("Barbell Rear Delt Row", reason: "Heavier experienced option", new: 4, experienced: 0)
            ]
        ),
        slot(
            "pull-lat-focus",
            "Lat isolation",
            "Train shoulder extension without another heavy row.",
            muscle: .back,
            sets: 3,
            reps: 12,
            rest: 75,
            candidates: [
                candidate("Straight-Arm Pulldown", reason: "Direct cable lat work", new: 0, experienced: 0),
                candidate("Rope Straight-Arm Pulldown", reason: "Comfortable rope variation", new: 1, experienced: 1),
                candidate("Bent-Arm Dumbbell Pullover", reason: "Dumbbell pullover option", profiles: dumbbellOnly, new: 1, experienced: 0),
                candidate("Straight-Arm Dumbbell Pullover", reason: "Long-range dumbbell option", profiles: dumbbellOnly, new: 2, experienced: 1),
                candidate("Scapular Pull-Up", reason: "Bodyweight shoulder control", profiles: minimalOnly, new: 0, experienced: 1),
                candidate("Rocky Pull-Ups/Pulldowns", reason: "Advanced bodyweight challenge", profiles: minimalOnly, minimum: .expert, new: 4, experienced: 0)
            ]
        ),
        slot(
            "pull-biceps",
            "Biceps",
            "Finish with direct elbow-flexion work.",
            muscle: .biceps,
            sets: 3,
            reps: 12,
            rest: 75,
            candidates: [
                candidate("Dumbbell Curl", aliases: ["Dumbbell Bicep Curl"], reason: "The familiar dumbbell staple", profiles: dumbbellOnly, new: 1, experienced: 1),
                candidate("Barbell Curl", aliases: ["EZ-Bar Curl"], reason: "Easy to load progressively", new: 3, experienced: 0),
                candidate("Cable Curl", aliases: ["Cable Preacher Curl"], reason: "Smooth cable resistance", new: 1, experienced: 2),
                candidate("Machine Bicep Curl", reason: "Stable and easy to learn", new: 0, experienced: 3),
                candidate("Band Assisted Pull-Up", aliases: ["Pull-Up"], reason: "Scalable bodyweight biceps work", profiles: minimalOnly, new: 0, experienced: 2),
                candidate("Chin-Up", reason: "Compound bodyweight curl", profiles: dumbbellOrMinimal, new: 2, experienced: 0),
                candidate("Reverse Plate Curls", reason: "Simple minimal-equipment curl", profiles: minimalOnly, new: 1, experienced: 1)
            ]
        )
    ]

    private static let core: [GuidedMovementSlot] = [
        slot(
            "core-extension",
            "Resist extension",
            "Keep the ribs and pelvis controlled as the lever gets longer.",
            muscle: .core,
            sets: 3,
            reps: 10,
            rest: 60,
            candidates: [
                candidate("Dead Bug", reason: "Excellent place to begin", profiles: dumbbellOrMinimal, new: 0, experienced: 3),
                candidate("Ab Wheel Rollout", aliases: ["Barbell Ab Rollout - On Knees"], reason: "The standard anti-extension progression", minimum: .intermediate, new: 3, experienced: 1),
                candidate("Barbell Ab Rollout", reason: "Advanced anti-extension work", minimum: .expert, new: 5, experienced: 0),
                candidate("Barbell Rollout from Bench", reason: "Supported rollout progression", minimum: .intermediate, new: 4, experienced: 2),
                candidate("Tuck Crunch", reason: "Bodyweight control alternative", profiles: minimalOnly, new: 1, experienced: 4)
            ]
        ),
        slot(
            "core-rotation-control",
            "Rotation control",
            "Control the torso through anti-rotation and diagonal movement.",
            muscle: .core,
            sets: 3,
            reps: 12,
            rest: 60,
            candidates: [
                candidate("Pallof Press", reason: "Clear anti-rotation staple", new: 0, experienced: 0),
                candidate("Standing Cable Wood Chop", reason: "Controlled diagonal resistance", new: 1, experienced: 1),
                candidate("Russian Twist", reason: "No-machine rotational option", profiles: dumbbellOrMinimal, new: 2, experienced: 0),
                candidate("Pallof Press With Rotation", reason: "Progressive cable control", new: 3, experienced: 2),
                candidate("Cable Russian Twists", reason: "Loadable cable rotation", new: 4, experienced: 1)
            ]
        ),
        slot(
            "core-flexion",
            "Controlled flexion",
            "Train the abdominals through a controlled curl.",
            muscle: .core,
            sets: 3,
            reps: 12,
            rest: 60,
            candidates: [
                candidate("Ab Crunch Machine", reason: "Stable and easy to load", new: 0, experienced: 2),
                candidate("Cable Crunch", reason: "Smooth progressive resistance", new: 1, experienced: 0),
                candidate("Reverse Crunch", reason: "Reliable bodyweight option", profiles: dumbbellOrMinimal, new: 0, experienced: 1),
                candidate("Exercise Ball Crunch", reason: "Comfortable extended range", profiles: dumbbellOrMinimal, new: 1, experienced: 3),
                candidate("Crunches", reason: "No equipment needed", profiles: minimalOnly, new: 2, experienced: 4)
            ]
        ),
        slot(
            "core-lower",
            "Lower core",
            "Train controlled hip and pelvic movement without swinging.",
            muscle: .core,
            sets: 3,
            reps: 10,
            rest: 60,
            candidates: [
                candidate("Flat Bench Lying Leg Raise", reason: "Supported bodyweight option", profiles: dumbbellOrMinimal, new: 0, experienced: 2),
                candidate("Cable Reverse Crunch", reason: "Loadable cable progression", new: 1, experienced: 1),
                candidate("Hanging Leg Raise", reason: "Advanced bodyweight option", profiles: minimalOnly, minimum: .intermediate, new: 4, experienced: 0),
                candidate("Decline Reverse Crunch", reason: "Progressive bodyweight variation", profiles: minimalOnly, new: 2, experienced: 1),
                candidate("Suspended Reverse Crunch", reason: "Advanced suspended variation", profiles: minimalOnly, minimum: .expert, new: 5, experienced: 0)
            ]
        ),
        slot(
            "core-side",
            "Side core",
            "Strengthen the obliques with controlled side bending.",
            muscle: .core,
            sets: 3,
            reps: 12,
            rest: 60,
            candidates: [
                candidate("Dumbbell Side Bend", reason: "Simple dumbbell oblique work", profiles: dumbbellOnly, new: 0, experienced: 1),
                candidate("One-Arm High-Pulley Cable Side Bends", reason: "Smooth cable resistance", new: 1, experienced: 2),
                candidate("Kettlebell Windmill", reason: "Advanced side-core control", profiles: dumbbellOnly, minimum: .intermediate, new: 4, experienced: 0),
                candidate("Barbell Side Bend", reason: "Loadable barbell option", new: 3, experienced: 1),
                candidate("Oblique Crunches - On The Floor", reason: "No-equipment alternative", profiles: minimalOnly, new: 0, experienced: 3)
            ]
        ),
        slot(
            "core-posterior",
            "Posterior trunk",
            "Balance the session with controlled back-side trunk strength.",
            muscle: .back,
            sets: 3,
            reps: 12,
            rest: 75,
            candidates: [
                candidate("Hyperextensions (Back Extensions)", reason: "Supported and easy to scale", new: 0, experienced: 1),
                candidate("Hyperextensions With No Hyperextension Bench", reason: "Bodyweight floor option", profiles: dumbbellOrMinimal, new: 1, experienced: 3),
                candidate("Reverse Hyperextension", reason: "Stable posterior-chain machine", new: 1, experienced: 0),
                candidate("Weighted Ball Hyperextension", reason: "Progressive stability-ball option", profiles: dumbbellOrMinimal, new: 2, experienced: 1),
                candidate("Band Good Morning (Pull Through)", reason: "Portable posterior-chain option", profiles: minimalOnly, new: 2, experienced: 0)
            ]
        )
    ]

    private static func slot(
        _ id: String,
        _ title: String,
        _ purpose: String,
        muscle: MuscleGroup,
        sets: Int,
        reps: Int,
        rest: Int,
        candidates: [GuidedExerciseCandidateDefinition]
    ) -> GuidedMovementSlot {
        GuidedMovementSlot(
            id: id,
            title: title,
            purpose: purpose,
            fallbackMuscle: muscle,
            setCount: sets,
            repetitions: reps,
            restSeconds: rest,
            candidates: candidates
        )
    }

    private static func candidate(
        _ name: String,
        aliases: [String] = [],
        reason: String,
        profiles: Set<GuidedRoutineEquipmentProfile> = [],
        minimum: GuidedRoutineExperience = .beginner,
        new: Int,
        experienced: Int
    ) -> GuidedExerciseCandidateDefinition {
        GuidedExerciseCandidateDefinition(
            name,
            aliases: aliases,
            reason: reason,
            profiles: profiles,
            newRank: new,
            experiencedRank: experienced,
            minimumExperience: minimum
        )
    }
}

enum GuidedExerciseResolver {
    private struct ResolvedCandidate {
        let declarationIndex: Int
        let definition: GuidedExerciseCandidateDefinition
        let exercise: Exercise
        let supportsEquipmentProfile: Bool
        let popularityRank: Int
    }

    static func options(
        for slot: GuidedMovementSlot,
        experience: GuidedRoutineExperience,
        equipmentProfile: GuidedRoutineEquipmentProfile,
        exercises: [Exercise]
    ) throws -> [GuidedResolvedExerciseOption] {
        let active = exercises.filter {
            !$0.isArchived
                && equipmentProfile.accepts($0.equipment)
                && supportsRepetitionTargets($0.measurementType)
        }
        let lookup = Dictionary(grouping: active) { exercise in
            ExerciseNameNormalizer.normalize(exercise.name)
        }

        let gatedExerciseIDs = Set(
            slot.candidates
                .filter { !$0.isAvailable(to: experience) }
                .flatMap { matchingExercises($0, lookup: lookup) }
                .map(\.id)
        )

        let orderedCandidates: [ResolvedCandidate] = slot.candidates.enumerated().compactMap { element in
            let (index, candidate) = element
            guard candidate.isAvailable(to: experience),
                  let exercise = resolve(candidate, lookup: lookup)
            else { return nil }
            return ResolvedCandidate(
                declarationIndex: index,
                definition: candidate,
                exercise: exercise,
                supportsEquipmentProfile: candidate.supports(equipmentProfile),
                popularityRank: canonicalPopularityRank(for: candidate, exercise: exercise)
            )
        }.sorted { lhs, rhs in
            if lhs.supportsEquipmentProfile != rhs.supportsEquipmentProfile {
                return lhs.supportsEquipmentProfile
            }
            if lhs.popularityRank != rhs.popularityRank {
                return lhs.popularityRank < rhs.popularityRank
            }
            let lhsRank = lhs.definition.rank(for: experience)
            let rhsRank = rhs.definition.rank(for: experience)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.declarationIndex < rhs.declarationIndex
        }

        var resolved: [(GuidedExerciseCandidateDefinition, Exercise)] = []
        var usedExerciseIDs = Set<UUID>()

        for candidate in orderedCandidates {
            guard usedExerciseIDs.insert(candidate.exercise.id).inserted else { continue }
            resolved.append((candidate.definition, candidate.exercise))
            if resolved.count == 3 { break }
        }

        if resolved.count < 3 {
            let fallbacks = active
                .filter { exercise in
                    exercise.primaryMuscleGroup == slot.fallbackMuscle
                        && !usedExerciseIDs.contains(exercise.id)
                        && !gatedExerciseIDs.contains(exercise.id)
                }
                .sorted { lhs, rhs in
                    let lhsAccepted = equipmentProfile.accepts(lhs.equipment)
                    let rhsAccepted = equipmentProfile.accepts(rhs.equipment)
                    if lhsAccepted != rhsAccepted { return lhsAccepted }
                    let lhsPopularity = canonicalPopularityRank(for: lhs)
                    let rhsPopularity = canonicalPopularityRank(for: rhs)
                    if lhsPopularity != rhsPopularity {
                        return lhsPopularity < rhsPopularity
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }

            for exercise in fallbacks where resolved.count < 3 {
                guard usedExerciseIDs.insert(exercise.id).inserted else { continue }
                let fallback = GuidedExerciseCandidateDefinition(
                    exercise.name,
                    reason: "Popular \(slot.fallbackMuscle.displayName.lowercased()) option",
                    profiles: [],
                    newRank: 99,
                    experiencedRank: 99
                )
                resolved.append((fallback, exercise))
            }
        }

        guard resolved.count == 3 else {
            throw GuidedRoutineBuilderError.incompleteSlot(slot.title)
        }

        return resolved.enumerated().map { index, pair in
            GuidedResolvedExerciseOption(
                candidateID: pair.0.id,
                exercise: pair.1,
                reason: pair.0.reason,
                isRecommended: index == 0
            )
        }
    }

    private static func resolve(
        _ candidate: GuidedExerciseCandidateDefinition,
        lookup: [String: [Exercise]]
    ) -> Exercise? {
        matchingExercises(candidate, lookup: lookup).first
    }

    private static func matchingExercises(
        _ candidate: GuidedExerciseCandidateDefinition,
        lookup: [String: [Exercise]]
    ) -> [Exercise] {
        var seen = Set<UUID>()
        return candidate.preferredNames.flatMap { name in
            lookup[ExerciseNameNormalizer.normalize(name)]?.sorted(by: preferredExerciseOrder) ?? []
        }.filter { seen.insert($0.id).inserted }
    }

    private static func preferredExerciseOrder(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        if lhs.isCustom != rhs.isCustom { return !lhs.isCustom }
        let lhsPopularity = canonicalPopularityRank(for: lhs)
        let rhsPopularity = canonicalPopularityRank(for: rhs)
        if lhsPopularity != rhsPopularity { return lhsPopularity < rhsPopularity }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func canonicalPopularityRank(
        for candidate: GuidedExerciseCandidateDefinition,
        exercise: Exercise
    ) -> Int {
        (candidate.preferredNames + [exercise.name] + exercise.searchAliases).reduce(
            exercise.popularityRank
        ) { bestRank, name in
            min(bestRank, ExercisePopularity.rank(for: name))
        }
    }

    private static func canonicalPopularityRank(for exercise: Exercise) -> Int {
        ([exercise.name] + exercise.searchAliases).reduce(exercise.popularityRank) { bestRank, name in
            min(bestRank, ExercisePopularity.rank(for: name))
        }
    }

    private static func supportsRepetitionTargets(_ measurementType: MeasurementType) -> Bool {
        switch measurementType {
        case .weightAndRepetitions,
             .repetitionsOnly,
             .bodyweightAndRepetitions,
             .bodyweightPlusAddedWeight,
             .assistedBodyweight:
            true
        case .duration,
             .weightAndDuration,
             .distanceAndDuration,
             .custom:
            false
        }
    }
}

enum GuidedRoutineFactory {
    static func makeRoutine(
        name: String,
        colorPreset: RoutineColorPreset,
        duration: GuidedRoutineDuration,
        selections: [GuidedRoutineSelection]
    ) -> Routine {
        let routine = Routine(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: "Built with Rep’s guided routine builder.",
            colorPreset: colorPreset
        )

        for selection in selections {
            routine.appendExercise(RoutineExercise(
                exercise: selection.exercise,
                targetSetCount: selection.slot.setCount(for: duration),
                suggestedRepetitions: selection.slot.repetitions,
                defaultRestSeconds: selection.slot.restSeconds
            ))
        }
        return routine
    }
}
