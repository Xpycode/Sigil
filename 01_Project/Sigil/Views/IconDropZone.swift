import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Square drop zone that accepts image files (PNG/JPEG/HEIC) and `.icns`
/// files, either via drag-and-drop or click-to-browse. When a source is
/// pending, renders the caller-supplied preview image in place of the
/// drop-zone prompt.
struct IconDropZone: View {

    /// User-picked source URL. Parent owns the binding; writing to it
    /// triggers the preview rendering via the parent's `.onChange`.
    @Binding var pendingSource: URL?

    /// Parent-rendered preview of `pendingSource` applied to current FitMode.
    /// When `nil` with a pending source, a spinner is shown.
    let previewImage: NSImage?

    /// The icon currently applied to this volume (loaded from cache). Shown
    /// when no source is pending, so the user sees what's on the volume
    /// instead of the generic "Drop image here" prompt.
    let currentIcon: NSImage?

    @State private var isTargeted: Bool = false
    @State private var showPicker: Bool = false

    private static let allowedImageTypes: [UTType] = [
        .png,
        .jpeg,
        .heic,
        UTType("com.apple.icns") ?? .data,
    ]

    var body: some View {
        Button { showPicker = true } label: {
            zone
                .frame(width: 200, height: 200)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: Self.allowedImageTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingSource = url
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            pendingSource = url
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    @ViewBuilder
    private var zone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isTargeted
                        ? Theme.accent.opacity(0.15)
                        : Theme.elevatedBackground.opacity(0.45)
                )

            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [7, 4])
                )
                .foregroundStyle(isTargeted ? Theme.accent : Theme.separator)

            content
                .padding(contentPadding)

            if pendingSource != nil {
                clearButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    /// Small overlay button that clears `pendingSource`. Lives *inside* the
    /// zone's ZStack so it sits on top of the preview image; because it's a
    /// `Button`, it swallows its own hit and won't trigger the parent
    /// click-to-browse action.
    private var clearButton: some View {
        Button { pendingSource = nil } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.secondaryText, Theme.elevatedBackground.opacity(0.9))
        }
        .buttonStyle(.plain)
        .help("Clear")
    }

    /// Empty state needs breathing room around the prompt text; when there's
    /// an image to show, keep the inset minimal so the preview fills the zone.
    private var contentPadding: CGFloat {
        (pendingSource != nil || currentIcon != nil) ? 2 : 16
    }

    @ViewBuilder
    private var content: some View {
        if let image = previewImage ?? currentIcon {
            ZStack(alignment: .bottom) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if isTargeted {
                    Text("Drop to replace")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                        .padding(.bottom, 8)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Drop or click to browse")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                Text("PNG · JPEG · HEIC · ICNS")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}
