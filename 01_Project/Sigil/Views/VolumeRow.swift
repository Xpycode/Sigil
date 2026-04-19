import SwiftUI

/// Compact row used in `SidebarView` for both mounted and remembered entries.
struct VolumeRow: View {
    let name: String
    let subtitle: String
    let isMounted: Bool
    let isRemembered: Bool
    /// When present, rendered in place of the SF Symbol — lets the sidebar
    /// display the actual icon Sigil applied for each remembered volume.
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 22, height: 22)
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
            if isRemembered {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .help("Remembered by Sigil")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var iconView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: isMounted ? "externaldrive.fill" : "externaldrive")
                .font(.system(size: 16))
                .foregroundStyle(isMounted ? Theme.accent : Theme.secondaryText)
        }
    }
}
