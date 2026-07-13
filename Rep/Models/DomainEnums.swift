import Foundation

protocol DisplayNamed {
    var displayName: String { get }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case chest, back, shoulders, biceps, triceps, quadriceps, hamstrings, glutes, calves, core
    case fullBody
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullBody: "Full body"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case barbell, dumbbell, machine, cable, bodyweight
    case smithMachine
    case kettlebell
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smithMachine: "Smith machine"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum MeasurementType: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case weightAndRepetitions
    case repetitionsOnly
    case duration
    case weightAndDuration
    case distanceAndDuration
    case bodyweightAndRepetitions
    case bodyweightPlusAddedWeight
    case assistedBodyweight
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightAndRepetitions: "Weight and repetitions"
        case .repetitionsOnly: "Repetitions"
        case .duration: "Duration"
        case .weightAndDuration: "Weight and duration"
        case .distanceAndDuration: "Distance and duration"
        case .bodyweightAndRepetitions: "Bodyweight and repetitions"
        case .bodyweightPlusAddedWeight: "Bodyweight plus added weight"
        case .assistedBodyweight: "Assisted bodyweight"
        case .custom: "Custom"
        }
    }

    var supportsExternalWeightVolume: Bool { self == .weightAndRepetitions }
}

enum WorkoutState: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case planned, active, completed, abandoned
    var id: String { rawValue }
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum WorkoutSetType: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case warmup, working, drop, failure, assisted, restPause, myoRep, amrap, timed
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .restPause: "Rest-pause"
        case .myoRep: "Myo-rep"
        case .amrap: "AMRAP"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum BodyweightSource: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case manual, healthKit, imported
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .healthKit: "HealthKit"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum PatternType: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case weekdayRoutine
    case routineTransition
    case rotation
    case exerciseSequence
    case preferredFirstExercise
    case frequentSubstitution
    case typicalSetStructure
    case typicalRestDuration

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .weekdayRoutine: "Weekday routine"
        case .routineTransition: "Routine transition"
        case .rotation: "Routine rotation"
        case .exerciseSequence: "Exercise sequence"
        case .preferredFirstExercise: "Preferred first exercise"
        case .frequentSubstitution: "Frequent substitution"
        case .typicalSetStructure: "Typical set structure"
        case .typicalRestDuration: "Typical rest duration"
        }
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case kilograms, pounds
    var id: String { rawValue }
    var symbol: String { self == .kilograms ? "kg" : "lb" }
    var displayName: String { self == .kilograms ? "Kilograms" : "Pounds" }
}

enum ProgressTimeRange: String, Codable, CaseIterable, Identifiable, Sendable, DisplayNamed {
    case thirtyDays, ninetyDays, sixMonths, oneYear, allTime
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .sixMonths: "6 months"
        case .oneYear: "One year"
        case .allTime: "All time"
        }
    }
}
