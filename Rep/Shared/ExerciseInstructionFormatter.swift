import Foundation

enum ExerciseInstructionFormatter {
    /// Parses stored instruction text into clean, display-ready steps.
    static func steps(from raw: String) -> [String] {
        raw
            .components(separatedBy: .newlines)
            .map(formatStep)
            .filter { !$0.isEmpty }
    }

    /// Formats imported instruction lines for storage.
    static func joined(from steps: [String]) -> String {
        steps
            .map(formatStep)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func formatStep(_ raw: String) -> String {
        var step = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { return "" }

        step = step.replacingOccurrences(
            of: #"(?i)^\s*step\s*:\s*\d+\.?\s*"#,
            with: "",
            options: .regularExpression
        )
        step = step.replacingOccurrences(
            of: #"(?i)^\s*step\s+\d+\.?\s*"#,
            with: "",
            options: .regularExpression
        )
        step = step.replacingOccurrences(
            of: #"^\s*(?:\d+[.)]|[-•])\s*"#,
            with: "",
            options: .regularExpression
        )
        step = step.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        step = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { return "" }

        return capitalizeFirstLetter(step)
    }

    private static func capitalizeFirstLetter(_ value: String) -> String {
        guard let first = value.first else { return value }
        guard first.isLowercase else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}
