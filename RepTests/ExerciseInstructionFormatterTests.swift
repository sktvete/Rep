import Foundation
import Testing
@testable import Rep

@Suite("Exercise instruction formatting")
struct ExerciseInstructionFormatterTests {
    @Test("Provider step prefixes are removed")
    func providerSteps() {
        let raw = """
        Step:1 Lie face down on the floor with your legs extended behind you.

        Step:2 Place your hands on the floor next to your lower ribs, fingers pointing forward.
        """

        let steps = ExerciseInstructionFormatter.steps(from: raw)

        #expect(steps.count == 2)
        #expect(steps[0] == "Lie face down on the floor with your legs extended behind you.")
        #expect(steps[1] == "Place your hands on the floor next to your lower ribs, fingers pointing forward.")
    }

    @Test("Numbered and bullet prefixes are removed")
    func listPrefixes() {
        let raw = """
        1. Set the bar on the rack.
        - Brace your core.
        • Drive up through your heels.
        """

        let steps = ExerciseInstructionFormatter.steps(from: raw)

        #expect(steps == [
            "Set the bar on the rack.",
            "Brace your core.",
            "Drive up through your heels.",
        ])
    }

    @Test("Joined instructions are cleaned before storage")
    func joinedInstructions() {
        let joined = ExerciseInstructionFormatter.joined(from: [
            "Step:1 Adjust the cable pulleys to chest height.",
            "Step:2 Grab the handles with palms facing down.",
        ])

        #expect(joined.contains("Adjust the cable pulleys to chest height."))
        #expect(!joined.localizedCaseInsensitiveContains("step:"))
    }
}
