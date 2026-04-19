import Foundation
import CryptoKit

enum Hashing {
    /// Lowercase hex string of SHA-256(data). Used for `lastAppliedHash` in
    /// `VolumeRecord` to detect external modification of `.VolumeIcon.icns`.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
