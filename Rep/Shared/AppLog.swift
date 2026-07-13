import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Rep"

    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let timer = Logger(subsystem: subsystem, category: "RestTimer")

    static func persistenceFailure(operation: String, error: Error) {
        persistence.error(
            "\(operation, privacy: .public) failed: \(String(describing: error), privacy: .public)"
        )
    }
}

