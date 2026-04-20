import Foundation

/// Manages the per-volume icon files Sigil keeps in
/// `~/Library/Application Support/Sigil/icons/`.
///
/// Two kinds of files:
/// - `{uuid}.icns`   — the rendered icon Sigil wrote to the volume (used by
///                     smart-silent re-apply on remount)
/// - `{uuid}.src.*`  — a copy of the user's original source image, preserved
///                     so Fit/Fill toggling doesn't require a re-import
enum IconCache {

    /// Save the rendered `.icns` for a volume identity. Atomic write.
    @discardableResult
    static func saveIcns(_ data: Data, for identity: VolumeIdentity) throws -> URL {
        let url = try icnsURL(for: identity)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Load the cached `.icns` bytes, or `nil` if absent.
    static func loadIcns(for identity: VolumeIdentity) throws -> Data? {
        let url = try icnsURL(for: identity)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Copy the user's source image into the cache so later Fit/Fill toggles
    /// can re-render without asking the user to re-import. Returns the cached URL.
    @discardableResult
    static func saveSource(_ sourceURL: URL, for identity: VolumeIdentity) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased().isEmpty ? "bin" : sourceURL.pathExtension.lowercased()
        let destURL = try iconsDir()
            .appendingPathComponent("\(identity.raw).src.\(ext)")

        // Re-applying an already-cached source (e.g. just re-zoom): source and
        // dest are the same file — nothing to copy, and we must not delete it.
        if sourceURL.standardizedFileURL == destURL.standardizedFileURL {
            return destURL
        }

        // Clear any stale `.src.*` for this identity — a new source may have a
        // different extension than the previous one, and `sourceURL(for:)`
        // picks whatever it finds first, so leaving two would be ambiguous.
        let dir = try iconsDir()
        let prefix = "\(identity.raw).src."
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let fm = FileManager.default
        for name in contents where name.hasPrefix(prefix) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }

        try fm.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    /// Find the cached source file for a volume identity (unknown extension).
    static func sourceURL(for identity: VolumeIdentity) throws -> URL? {
        let dir = try iconsDir()
        let prefix = "\(identity.raw).src."
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        guard let name = contents.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return dir.appendingPathComponent(name)
    }

    /// Delete every cached file for a volume identity (`.icns` and any `.src.*`).
    /// Silently ignores already-absent files.
    static func delete(for identity: VolumeIdentity) throws {
        let dir = try iconsDir()
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let prefix = identity.raw
        for name in contents where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - URL helpers

    private static func iconsDir() throws -> URL {
        try AppPaths.iconsDir()
    }

    static func icnsURL(for identity: VolumeIdentity) throws -> URL {
        try iconsDir().appendingPathComponent("\(identity.raw).icns")
    }
}
