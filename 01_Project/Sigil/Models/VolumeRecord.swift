import Foundation

/// One persisted entry in `volumes.json`. Keyed by volume UUID; contains
/// everything Sigil needs to re-apply an icon when the volume remounts.
struct VolumeRecord: Codable, Sendable, Hashable, Identifiable {

    /// Volume UUID. Encoded as `"uuid"` in JSON.
    let identity: VolumeIdentity

    /// Last-known volume name (display only — not used as identity).
    var name: String

    /// User-supplied free-text note. Empty string when unset.
    var note: String

    /// Last time Sigil saw this volume mounted.
    var lastSeen: Date

    /// When Sigil last successfully wrote `.VolumeIcon.icns` for this volume.
    var lastApplied: Date?

    /// SHA-256 (hex) of the `.VolumeIcon.icns` Sigil last wrote. Used for the
    /// smart-silent reapply / conflict detection on remount.
    var lastAppliedHash: String?

    /// Fit/Fill mode chosen by the user when the source image was imported.
    var fitMode: FitMode

    /// Original filename of the imported source (for display only).
    var sourceFilename: String?

    var id: String { identity.raw }

    init(
        identity: VolumeIdentity,
        name: String,
        note: String = "",
        lastSeen: Date = Date(),
        lastApplied: Date? = nil,
        lastAppliedHash: String? = nil,
        fitMode: FitMode = .fit,
        sourceFilename: String? = nil
    ) {
        self.identity = identity
        self.name = name
        self.note = note
        self.lastSeen = lastSeen
        self.lastApplied = lastApplied
        self.lastAppliedHash = lastAppliedHash
        self.fitMode = fitMode
        self.sourceFilename = sourceFilename
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, name, note, lastSeen, lastApplied, lastAppliedHash, fitMode, sourceFilename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identity = VolumeIdentity(try c.decode(String.self, forKey: .uuid))
        self.name = try c.decode(String.self, forKey: .name)
        self.note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        self.lastApplied = try c.decodeIfPresent(Date.self, forKey: .lastApplied)
        self.lastAppliedHash = try c.decodeIfPresent(String.self, forKey: .lastAppliedHash)
        self.fitMode = try c.decodeIfPresent(FitMode.self, forKey: .fitMode) ?? .fit
        self.sourceFilename = try c.decodeIfPresent(String.self, forKey: .sourceFilename)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identity.raw, forKey: .uuid)
        try c.encode(name, forKey: .name)
        try c.encode(note, forKey: .note)
        try c.encode(lastSeen, forKey: .lastSeen)
        try c.encodeIfPresent(lastApplied, forKey: .lastApplied)
        try c.encodeIfPresent(lastAppliedHash, forKey: .lastAppliedHash)
        try c.encode(fitMode, forKey: .fitMode)
        try c.encodeIfPresent(sourceFilename, forKey: .sourceFilename)
    }
}
