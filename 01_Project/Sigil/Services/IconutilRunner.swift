import Foundation

/// Thin subprocess wrapper around `/usr/bin/iconutil -c icns`. Captures stderr
/// for diagnostics; enforces a 30-second timeout; cleans up the intermediate
/// `.icns` file after reading it.
enum IconutilRunner {

    static let executable = URL(fileURLWithPath: "/usr/bin/iconutil")
    static let timeoutSeconds: UInt64 = 30

    enum Error: LocalizedError {
        case launchFailed(underlying: Swift.Error)
        case timedOut
        case nonZeroExit(status: Int32, stderr: String)
        case outputMissing(expected: URL)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let err):
                return "Could not launch iconutil: \(err.localizedDescription)"
            case .timedOut:
                return "iconutil timed out after \(IconutilRunner.timeoutSeconds) seconds."
            case .nonZeroExit(let status, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "iconutil exited \(status)" + (trimmed.isEmpty ? "." : ": \(trimmed)")
            case .outputMissing(let url):
                return "iconutil reported success but \(url.lastPathComponent) was not produced."
            }
        }
    }

    /// Convert a `.iconset/` directory to `.icns` bytes.
    ///
    /// - Parameter iconsetDir: Directory containing PNGs named per
    ///   `IconsetWriter.specs`. Must exist.
    /// - Returns: Raw `.icns` data.
    static func convert(iconsetDir: URL) async throws -> Data {
        let outputURL = iconsetDir
            .deletingPathExtension()
            .appendingPathExtension("icns")

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-c", "icns", "-o", outputURL.path, iconsetDir.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        // Bridge Process's callback-based termination into async/await.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Swift.Error>) in
            process.terminationHandler = { _ in cont.resume() }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: Error.launchFailed(underlying: error))
            }
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw Error.nonZeroExit(status: process.terminationStatus, stderr: stderr)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw Error.outputMissing(expected: outputURL)
        }

        let data = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        return data
    }
}
