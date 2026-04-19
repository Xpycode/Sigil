import Foundation

/// Centralized location service for everything Sigil writes to disk.
/// All accessors create their parent directories on first read.
enum AppPaths {

    /// `~/Library/Application Support/Sigil/`
    static func appSupport() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Sigil", isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    /// `~/Library/Application Support/Sigil/icons/` — cached source images and rendered .icns files.
    static func iconsDir() throws -> URL {
        let dir = try appSupport().appendingPathComponent("icons", isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    /// `~/Library/Application Support/Sigil/logs/` — diagnostic logs (rolling).
    static func logsDir() throws -> URL {
        let dir = try appSupport().appendingPathComponent("logs", isDirectory: true)
        try ensureDirectory(at: dir)
        return dir
    }

    /// `~/Library/Application Support/Sigil/volumes.json` — primary store.
    static func volumesJSON() throws -> URL {
        try appSupport().appendingPathComponent("volumes.json")
    }

    /// `~/Library/Application Support/Sigil/volumes.json.bak` — single rolling backup.
    static func volumesJSONBackup() throws -> URL {
        try appSupport().appendingPathComponent("volumes.json.bak")
    }

    private static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw AppPathsError.notADirectory(url)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

enum AppPathsError: LocalizedError {
    case notADirectory(URL)

    var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            return "Expected a directory at \(url.path), but found a file."
        }
    }
}
