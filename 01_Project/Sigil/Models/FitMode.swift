import Foundation

/// How a non-square source image is fitted into the square icon canvas.
enum FitMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Letterbox the image inside the canvas; pad with transparent pixels.
    case fit
    /// Center-crop the image to fill the canvas.
    case fill

    var displayName: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        }
    }
}
