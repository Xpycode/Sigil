import Foundation
import AppKit

/// The actor responsible for actually making Finder display a custom icon on
/// a volume. Performs the two-step write required on macOS 13.1+:
///
///   1. Write `.VolumeIcon.icns` at the volume root (atomic).
///   2. Read `com.apple.FinderInfo` (32 bytes), set byte 8 to `0x04`
///      (`kHasCustomIcon`), write it back — preserving any other flags
///      (Finder label color etc.) the user may have set.
///   3. `utimes` the volume root to nudge Finder's icon cache.
///
/// `NSWorkspace.setIcon(_:forFile:options:)` is explicitly NOT used — it
/// writes the file but silently fails to set the flag on volume roots since
/// macOS 13.1. See `docs/decisions.md` 2026-04-19.
actor IconApplier {

    /// Name of the hidden icon file at a volume's root.
    static let iconFilename = ".VolumeIcon.icns"

    /// Extended-attribute key where the custom-icon flag lives.
    static let finderInfoKey = "com.apple.FinderInfo"

    /// Offset of the `kHasCustomIcon` flag inside the 32-byte FinderInfo blob.
    static let customIconByteOffset = 8

    /// Value of the `kHasCustomIcon` flag at that byte.
    static let customIconFlag: UInt8 = 0x04

    /// Canonical length of `com.apple.FinderInfo`.
    static let finderInfoLength = 32

    /// Extra bytes reserved beyond the icns size for the disk-space preflight.
    private static let diskSlackBytes = 64 * 1024

    enum Error: LocalizedError {
        case notAVolume(URL)
        case readOnly(URL)
        case permissionDenied(URL)
        case diskFull(URL, required: Int, available: Int?)
        case underlying(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .notAVolume(let url):
                return "\(url.path) is not a mounted volume root."
            case .readOnly(let url):
                return "Can't write to '\(url.lastPathComponent)': volume is read-only."
            case .permissionDenied(let url):
                // Most commonly TCC denying removable-volume access (macOS 13+).
                // Point the user at the exact System Settings pane to fix it.
                return "Can't write to '\(url.lastPathComponent)' — Sigil needs Removable Volumes access. Open System Settings → Privacy & Security → Files & Folders."
            case .diskFull(let url, let required, let available):
                let have = available.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "unknown"
                let need = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .file)
                return "Volume '\(url.lastPathComponent)' is full — need \(need), have \(have)."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    // MARK: - Apply

    /// Write `.VolumeIcon.icns` and set the FinderInfo flag. Returns the
    /// SHA-256 hex of the icns bytes for storage in `VolumeRecord.lastAppliedHash`.
    ///
    /// - Rolls back (deletes the orphan file) if the xattr step fails.
    @discardableResult
    func apply(icns: Data, to volumeURL: URL) async throws -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: volumeURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw Error.notAVolume(volumeURL)
        }

        // Disk-space preflight (cookbook 29): reject BEFORE we start writing.
        let required = icns.count + Self.diskSlackBytes
        let available = Self.freeSpaceBytes(at: volumeURL)
        if let available, available < required {
            throw Error.diskFull(volumeURL, required: required, available: available)
        }

        let iconURL = volumeURL.appendingPathComponent(Self.iconFilename)

        // Step 1: atomic write of the icns file.
        do {
            try icns.write(to: iconURL, options: [.atomic])
        } catch let err as CocoaError {
            throw Self.mapCocoaWriteError(err, url: volumeURL)
        } catch {
            throw Error.underlying(error)
        }

        // Step 2: read-modify-write FinderInfo to set byte 8 = 0x04.
        do {
            try Self.setCustomIconFlag(on: volumeURL)
        } catch {
            // Roll back the orphan icon file — otherwise we'd leave garbage.
            try? fm.removeItem(at: iconURL)
            throw Error.underlying(error)
        }

        // Step 3: nudge Finder's icon cache.
        Self.touchVolume(volumeURL)

        return Hashing.sha256Hex(icns)
    }

    // MARK: - Reset

    /// Remove the custom icon and clear the FinderInfo flag. Idempotent —
    /// safe to call when nothing has been applied.
    func reset(volumeURL: URL) async throws {
        let fm = FileManager.default
        let iconURL = volumeURL.appendingPathComponent(Self.iconFilename)

        if fm.fileExists(atPath: iconURL.path) {
            do {
                try fm.removeItem(at: iconURL)
            } catch let err as CocoaError {
                throw Self.mapCocoaWriteError(err, url: volumeURL)
            } catch {
                throw Error.underlying(error)
            }
        }

        do {
            try Self.clearCustomIconFlag(on: volumeURL)
        } catch {
            throw Error.underlying(error)
        }

        Self.touchVolume(volumeURL)
    }

    // MARK: - Inspect

    /// SHA-256 hex of the current on-disk `.VolumeIcon.icns`, or `nil` if absent.
    func currentIconHash(volumeURL: URL) async -> String? {
        let iconURL = volumeURL.appendingPathComponent(Self.iconFilename)
        guard let data = try? Data(contentsOf: iconURL) else { return nil }
        return Hashing.sha256Hex(data)
    }

    /// Whether `com.apple.FinderInfo` on the volume root has the custom-icon flag.
    func hasCustomIconFlag(volumeURL: URL) async -> Bool {
        guard let info = try? XAttr.get(name: Self.finderInfoKey, from: volumeURL.path),
              info.count > Self.customIconByteOffset else {
            return false
        }
        return (info[Self.customIconByteOffset] & Self.customIconFlag) != 0
    }

    // MARK: - Private helpers

    private static func setCustomIconFlag(on volumeURL: URL) throws {
        var info = (try XAttr.get(name: finderInfoKey, from: volumeURL.path)) ?? Data()
        if info.count < finderInfoLength {
            info.append(contentsOf: [UInt8](repeating: 0, count: finderInfoLength - info.count))
        }
        info[customIconByteOffset] |= customIconFlag
        try XAttr.set(name: finderInfoKey, value: info, on: volumeURL.path)
    }

    private static func clearCustomIconFlag(on volumeURL: URL) throws {
        guard var info = try XAttr.get(name: finderInfoKey, from: volumeURL.path) else {
            return  // no FinderInfo present — nothing to clear
        }
        guard info.count > customIconByteOffset else { return }
        info[customIconByteOffset] &= ~customIconFlag

        // If every byte is now zero, remove the xattr entirely (cleaner).
        if info.allSatisfy({ $0 == 0 }) {
            try XAttr.remove(name: finderInfoKey, from: volumeURL.path)
        } else {
            try XAttr.set(name: finderInfoKey, value: info, on: volumeURL.path)
        }
    }

    private static func touchVolume(_ url: URL) {
        // Belt-and-braces Finder cache invalidation. Empirically (verified
        // against shasum-equal on-disk file vs. stale Finder thumbnail),
        // Finder's volume-icon cache lives in two buckets keyed by:
        //
        //   • the volume URL (the directory containing .VolumeIcon.icns)
        //   • the icns file URL itself (Finder treats the leading-dot
        //     hidden path as its own cache entry)
        //
        // Notifying only the volume URL was enough on a *first* apply
        // (no prior cache entry) but failed reliably on overwrites — same
        // hash on disk as Sigil's saved copy, but Finder kept showing the
        // previously-applied icon. So: bump mtime AND notify on both
        // paths. `iconset` and `fileicon` (the popular custom-icon CLIs)
        // do the same dual-notification dance.
        let iconURL = url.appendingPathComponent(iconFilename)
        utimes(url.path, nil)
        utimes(iconURL.path, nil)

        let workspace = NSWorkspace.shared
        workspace.noteFileSystemChanged(url.path)
        workspace.noteFileSystemChanged(iconURL.path)
    }

    private static func freeSpaceBytes(at url: URL) -> Int? {
        // ForImportantUsage is APFS-only — on ExFAT/FAT32/HFS+ it returns 0,
        // not nil, so a plain `if let` would falsely report a full disk.
        // Treat 0 as "no answer" and fall through to the legacy raw key.
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            return Int(important)
        }
        if let raw = values.volumeAvailableCapacity, raw > 0 {
            return raw
        }
        return nil
    }

    private static func mapCocoaWriteError(_ err: CocoaError, url: URL) -> Error {
        switch err.code {
        case .fileWriteVolumeReadOnly: return .readOnly(url)
        case .fileWriteNoPermission: return .permissionDenied(url)
        case .fileWriteOutOfSpace: return .diskFull(url, required: 0, available: nil)
        default: return .underlying(err)
        }
    }
}
