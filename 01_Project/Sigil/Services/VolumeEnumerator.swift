import Foundation

/// Enumerates currently-mounted volumes, with optional system filter.
///
/// "External only" (default) keeps removable, non-internal volumes — what a user
/// usually thinks of as "my external drives". "Show all" includes boot, recovery,
/// mounted DMGs, and so on.
actor VolumeEnumerator {

    static let resourceKeys: Set<URLResourceKey> = [
        .volumeUUIDStringKey,
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeIsRemovableKey,
        .volumeIsInternalKey,
        .volumeIsEjectableKey,
        .volumeIsBrowsableKey,
        .volumeIsRootFileSystemKey,
        .volumeLocalizedFormatDescriptionKey,
    ]

    /// Snapshot of currently-mounted volumes.
    /// - Parameter includeSystem: when `false`, applies Sigil's default
    ///   external filter (`isExternalForDefaultListing`). When `true`, returns
    ///   every browsable mount.
    func currentVolumes(includeSystem: Bool = false) -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(Self.resourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url -> VolumeInfo? in
            guard let info = Self.makeInfo(from: url) else { return nil }
            if !includeSystem, !info.isExternalForDefaultListing {
                return nil
            }
            return info
        }
    }

    /// Read metadata for a single mount-point URL.
    func info(for url: URL) -> VolumeInfo? {
        Self.makeInfo(from: url)
    }

    private static func makeInfo(from url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }
        let uuidStr = values.volumeUUIDString
        return VolumeInfo(
            identity: uuidStr.map { VolumeIdentity($0) },
            url: url,
            name: values.volumeName ?? url.lastPathComponent,
            capacityBytes: values.volumeTotalCapacity,
            isRemovable: values.volumeIsRemovable ?? false,
            isInternal: values.volumeIsInternal ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isRootFileSystem: values.volumeIsRootFileSystem ?? false,
            format: values.volumeLocalizedFormatDescription
        )
    }
}
