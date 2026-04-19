import Foundation

/// Snapshot of a currently-mounted volume at the moment Sigil enumerated it.
/// Backed by `URLResourceKey` lookups on the volume's mount-point URL.
struct VolumeInfo: Sendable, Hashable, Identifiable {

    /// Volume UUID (or DOS Volume Serial Number for FAT-family). `nil` for
    /// the rare volume that exposes no UUID (e.g., some ramdisks). Volumes
    /// without identity can be displayed but cannot be remembered.
    let identity: VolumeIdentity?

    /// Mount point, e.g. `file:///Volumes/Photos%20SSD/`.
    let url: URL

    /// User-visible volume name. Falls back to the URL's last path component.
    let name: String

    /// Total capacity in bytes; `nil` if not reported by the FS.
    let capacityBytes: Int?

    /// Physically removable media (SD card in a reader slot, optical disc).
    /// This is **NOT** the same as "external drive" — sealed external SSDs
    /// report `isRemovable == false`. Use `isEjectable` for the user-eject-able
    /// notion most apps mean by "external".
    let isRemovable: Bool

    /// Internal (boot, recovery, system) volume — connected on the internal bus.
    let isInternal: Bool

    /// User can eject from Finder / `diskutil eject` (external drives, DMGs,
    /// network shares, removable media). This is the right flag for "is it
    /// the kind of volume Sigil cares about?"
    let isEjectable: Bool

    /// The boot volume (mount point `/`).
    let isRootFileSystem: Bool

    /// Localized format description, e.g. "APFS", "exFAT", "MS-DOS (FAT32)".
    let format: String?

    var id: String { identity?.raw ?? url.path }

    /// Heuristic: this volume is a mounted disk image (DMG, ISO, etc.).
    /// Detected by mount path under `/Volumes/.timemachine/` or by absence
    /// of a parent device node — but the most reliable signal is that the
    /// underlying device is `/dev/disk*` whose disk image bit is set.
    /// We approximate via mount path heuristic.
    var isLikelyDiskImage: Bool {
        let path = url.path
        return path.contains("/.timemachine/") ||
               path.contains("/Snapshots/") ||
               // Common DMG mount roots
               path.hasPrefix("/Volumes/com.apple.")
    }

    /// Sigil's default "external" filter: ejectable, non-internal, non-boot,
    /// not a system-managed disk image.
    var isExternalForDefaultListing: Bool {
        guard !isRootFileSystem else { return false }
        guard !isInternal else { return false }
        guard !isLikelyDiskImage else { return false }
        return true
    }

    /// One-line summary for the detail pane "Type" row.
    ///
    /// Ordering matters: boot & disk-image take precedence, then internal-bus
    /// partitions, then specific removable/ejectable distinctions, then a
    /// catch-all "External" (USB/TB SSDs often report `isEjectable == false`
    /// because the media is sealed in the enclosure).
    var typeLabel: String {
        if isRootFileSystem { return "Boot" }
        if isLikelyDiskImage { return "Disk image" }
        if isInternal { return "Internal" }
        if isRemovable { return "Removable media" }
        return "External"
    }
}
