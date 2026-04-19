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
        VStack(spacing: 10) {
            zone
                .frame(minHeight: 220)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    pendingSource = url
                    return true
                } isTargeted: { targeted in
                    isTargeted = targeted
                }

            HStack {
                Button("Browse…") { showPicker = true }
                    .buttonStyle(.bordered)
                    .fileImporter(
                        isPresented: $showPicker,
                        allowedContentTypes: Self.allowedImageTypes,
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            pendingSource = url
                        }
                    }

                if pendingSource != nil {
                    Button("Clear") { pendingSource = nil }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer()
            }
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
                .padding(16)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    @ViewBuilder
    private var content: some View {
        if pendingSource != nil {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
        } else if let currentIcon {
            ZStack(alignment: .bottom) {
                Image(nsImage: currentIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
                Text("Drop image here")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                Text("PNG · JPEG · HEIC · ICNS")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}
