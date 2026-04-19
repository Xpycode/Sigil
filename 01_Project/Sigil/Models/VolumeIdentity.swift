import Foundation

/// Stable identifier for a volume. Backed by `URLResourceKey.volumeUUIDStringKey`,
/// which returns a real UUID for APFS/HFS+ and a DOS Volume Serial Number for
/// exFAT/FAT32 — both stable across mount cycles, both regenerated on reformat.
struct VolumeIdentity: Codable, Sendable, Hashable, CustomStringConvertible {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var description: String { raw }
}
