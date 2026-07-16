import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Rep"

    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let timer = Logger(subsystem: subsystem, category: "RestTimer")
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")

    static func persistenceFailure(operation: String, error: Error) {
        let description = String(describing: error)
        persistence.error(
            "\(operation, privacy: .public) failed: \(description, privacy: .public)"
        )
        Task {
            await DeveloperDiagnosticsStore.shared.record(
                level: "error",
                category: "persistence",
                message: "\(operation) failed: \(description)"
            )
        }
    }

    static func breadcrumb(_ message: String) {
        navigation.info("\(message, privacy: .public)")
        Task {
            await DeveloperDiagnosticsStore.shared.record(
                level: "info",
                category: "navigation",
                message: message
            )
        }
    }
}
