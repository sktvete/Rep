import Foundation
import MetricKit

/// Persists lightweight navigation breadcrumbs and Apple's post-crash MetricKit payloads.
/// MetricKit diagnostics are delivered on a later launch, so the surrounding breadcrumbs
/// help identify which screen was active immediately before an intermittent crash.
final class DeveloperDiagnosticsService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DeveloperDiagnosticsService()

    private let startLock = NSLock()
    private var hasStarted = false

    private override init() {
        super.init()
    }

    func start() {
        startLock.lock()
        guard !hasStarted else {
            startLock.unlock()
            return
        }
        hasStarted = true
        startLock.unlock()

        MXMetricManager.shared.add(self)
        Task {
            await DeveloperDiagnosticsStore.shared.record(
                level: "info",
                category: "lifecycle",
                message: "Diagnostics started"
            )
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashCount = payload.crashDiagnostics?.count ?? 0
            guard crashCount > 0 else { continue }

            // MXDiagnosticPayload is not Sendable; serialize it before crossing concurrency domains.
            let data = payload.jsonRepresentation()
            Task {
                await DeveloperDiagnosticsStore.shared.appendMetricKitPayload(
                    data,
                    crashCount: crashCount
                )
            }
        }
    }
}

actor DeveloperDiagnosticsStore {
    static let shared = DeveloperDiagnosticsStore()

    nonisolated static let fileURL: URL = {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("rep-diagnostics.log", isDirectory: false)
    }()

    private let maximumFileSize = 4 * 1_024 * 1_024

    func record(level: String, category: String, message: String) {
        let singleLineMessage = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        append(
            "[\(Self.timestamp())] [\(level)] [\(category)] \(singleLineMessage)\n"
        )
    }

    func appendMetricKitPayload(_ data: Data, crashCount: Int) {
        guard crashCount > 0 else { return }
        let payload = String(decoding: data, as: UTF8.self)
        append(
            "\n===== MetricKit crash payload · \(Self.timestamp()) · \(crashCount) crash(es) =====\n"
                + payload
                + "\n===== End MetricKit payload =====\n"
        )
    }

    func contents() throws -> String {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func clear() throws {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func append(_ text: String) {
        do {
            let url = Self.fileURL
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let newData = Data(text.utf8)
            if let existingData = try? Data(contentsOf: url),
               existingData.count + newData.count > maximumFileSize {
                let tail = String(
                    decoding: existingData.suffix(maximumFileSize / 2),
                    as: UTF8.self
                )
                let trimmedTail = tail.drop(while: { $0 != "\n" }).dropFirst()
                let rollover = "[\(Self.timestamp())] [info] [storage] Older diagnostics trimmed\n"
                    + trimmedTail
                    + text
                try Data(rollover.utf8).write(to: url, options: .atomic)
                return
            }

            if !fileManager.fileExists(atPath: url.path) {
                try newData.write(to: url, options: .atomic)
                return
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: newData)
        } catch {
            // Diagnostics must never become a source of another failure.
        }
    }

    private nonisolated static func timestamp() -> String {
        Date.now.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .dateSeparator(.dash)
                .time(includingFractionalSeconds: true)
                .timeSeparator(.colon)
        )
    }
}
