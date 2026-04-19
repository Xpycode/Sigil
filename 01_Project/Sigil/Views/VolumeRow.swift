import SwiftUI

/// Compact row used in `SidebarView` for both mounted and remembered entries.
struct VolumeRow: View {
    let name: String
    let subtitle: String
    let isMounted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isMounted ? "externaldrive.fill" : "externaldrive")
                .font(.system(size: 16))
                .foregroundStyle(isMounted ? Theme.accent : Theme.secondaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.callout)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
