import Foundation

/// Typical gym plate / stack increments for ± weight controls.
enum ExerciseWeightStep {
    static func step(for exercise: Exercise?, preferredUnit: WeightUnit) -> Double {
        let kilograms = kilogramsStep(for: exercise)
        switch preferredUnit {
        case .kilograms:
            return kilograms
        case .pounds:
            switch kilograms {
            case 1: return 2.5
            case 2.5: return 5
            default: return 10
            }
        }
    }

    /// Base step in kilograms before converting to the user's unit.
    static func kilogramsStep(for exercise: Exercise?) -> Double {
        guard let exercise else { return 5 }

        switch exercise.measurementType {
        case .assistedBodyweight:
            return 5
        case .bodyweightPlusAddedWeight:
            return 2.5
        case .repetitionsOnly, .duration, .distanceAndDuration, .bodyweightAndRepetitions:
            return 2.5
        case .weightAndRepetitions, .weightAndDuration, .custom:
            break
        }

        // Plate-loaded bars: +5 kg total (2.5 kg per side).
        switch exercise.equipment {
        case .barbell, .smithMachine:
            return 5
        case .dumbbell, .kettlebell, .cable, .machine, .bodyweight, .other:
            break
        }

        switch exercise.primaryMuscleGroup {
        case .shoulders, .biceps, .triceps, .calves:
            return 1
        case .chest, .back, .quadriceps, .hamstrings, .glutes, .core, .fullBody, .other:
            break
        }

        switch exercise.equipment {
        case .dumbbell, .kettlebell, .cable:
            return 2.5
        case .machine:
            return 5
        case .barbell, .smithMachine:
            return 5
        case .bodyweight, .other:
            return 2.5
        }
    }
}
