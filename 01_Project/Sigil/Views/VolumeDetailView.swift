import SwiftUI

/// Wave 3: shows basic info for the selected volume so selection is visible.
/// Full editor (icon drop, Fit/Fill, note, action buttons) wired in Wave 7.
struct VolumeDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let info = appState.selectedMounted {
                mountedDetail(info)
            } else if let record = appState.selectedRemembered {
                rememberedDetail(record)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.secondaryBackground)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Select a volume")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Mount an external drive or pick a remembered one in the sidebar.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    private func mountedDetail(_ info: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(info.format ?? "—")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }

            Divider().background(Theme.separator)

            keyValueRow("UUID", info.identity?.raw ?? "—", monospaced: true)
            keyValueRow("Mount", info.url.path)
            keyValueRow("Capacity", Self.formatBytes(info.capacityBytes))
            keyValueRow("Type", info.typeLabel)

            Divider().background(Theme.separator).padding(.top, 8)

            wave5SmokeTestBlock(info)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Wave 5 smoke test (temporary — removed in Wave 7)

    @ViewBuilder
    private func wave5SmokeTestBlock(_ info: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚠︎ Wave 5 smoke test")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text("Apply an orange test icon with the first 3 letters of this volume's name. Check Finder (sidebar + Get Info) to confirm. Use Reset to strip the icon and clear the flag. This block is removed in Wave 7.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Apply test icon") {
                    Task { await applyTestIcon(to: info) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button("Reset") {
                    Task { await resetIcon(on: info) }
                }
                .buttonStyle(.bordered)
            }

            if let status = smokeStatus {
                Text(status)
                    .font(.caption.monospaced())
                    .foregroundStyle(status.hasPrefix("✓") ? Theme.primaryText : Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.elevatedBackground.opacity(0.5))
        .cornerRadius(6)
    }

    @State private var smokeStatus: String? = nil

    private func applyTestIcon(to info: VolumeInfo) async {
        smokeStatus = "Rendering icon…"
        do {
            let image = TestIconFactory.makeIcon(label: info.name)
            let icns = try await IconRenderer.render(image: image)
            smokeStatus = "Writing to volume…"
            let applier = IconApplier()
            let hash = try await applier.apply(icns: icns, to: info.url)
            smokeStatus = "✓ Applied. Hash: \(hash.prefix(12))…"
        } catch {
            smokeStatus = "✗ \(error.localizedDescription)"
        }
    }

    private func resetIcon(on info: VolumeInfo) async {
        smokeStatus = "Resetting…"
        do {
            let applier = IconApplier()
            try await applier.reset(volumeURL: info.url)
            smokeStatus = "✓ Reset. Icon & flag removed."
        } catch {
            smokeStatus = "✗ \(error.localizedDescription)"
        }
    }

    private func rememberedDetail(_ record: VolumeRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Not mounted")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }

            Divider().background(Theme.separator)

            keyValueRow("UUID", record.identity.raw, monospaced: true)
            keyValueRow("Note", record.note.isEmpty ? "—" : record.note)
            keyValueRow("Last seen", record.lastSeen.formatted(date: .abbreviated, time: .shortened))
            if let applied = record.lastApplied {
                keyValueRow("Last applied", applied.formatted(date: .abbreviated, time: .shortened))
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Helpers

    private func keyValueRow(_ key: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 96, alignment: .trailing)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(Theme.primaryText)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private static func formatBytes(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
