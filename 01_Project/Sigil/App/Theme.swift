import SwiftUI
import AppKit

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var accentColor: Color {
        didSet { Self.saveColor(accentColor, forKey: Self.accentColorKey) }
    }

    private static let accentColorKey = "accentColor"
    private static let defaultAccent = Color(red: 0.9, green: 0.5, blue: 0.2)

    private init() {
        self.accentColor = Self.loadColor(forKey: Self.accentColorKey) ?? Self.defaultAccent
    }

    private static func saveColor(_ color: Color, forKey key: String) {
        let nsColor = NSColor(color)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        nsColor.encode(with: archiver)
        archiver.finishEncoding()
        UserDefaults.standard.set(archiver.encodedData, forKey: key)
    }

    private static func loadColor(forKey key: String) -> Color? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClass: NSColor.self, from: data
              ) else { return nil }
        return Color(nsColor: nsColor)
    }
}

enum Theme {
    static var primaryBackground: Color { Color(white: 0.10) }
    static var secondaryBackground: Color { Color(white: 0.15) }
    static var elevatedBackground: Color { Color(white: 0.20) }
    static var separator: Color { Color.white.opacity(0.08) }
    static var accent: Color { ThemeManager.shared.accentColor }
    static var primaryText: Color { .white }
    static var secondaryText: Color { .white.opacity(0.65) }
    static var tertiaryText: Color { .white.opacity(0.40) }
}
