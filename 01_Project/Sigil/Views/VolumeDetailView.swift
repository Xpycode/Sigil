import SwiftUI
import AppKit

struct VolumeDetailView: View {
    @Environment(AppState.self) private var appState

    // Editor state — reset on selection change via `.id(...)` on the parent Group.
    @State private var pendingSource: URL? = nil
    @State private var cachedSource: URL? = nil
    @State private var pendingMode: FitMode = .fit
    @State private var pendingZoom: Double = 1.0
    @State private var pendingNote: String = ""
    @State private var previewImage: NSImage? = nil
    @State private var currentIcon: NSImage? = nil
    @State private var noteDebounceTask: Task<Void, Never>? = nil

    @State private var isApplying: Bool = false
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil

    @State private var showResetConfirm: Bool = false
    @State private var showForgetConfirm: Bool = false

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

    // MARK: - Empty state

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

    // MARK: - Mounted detail

    private func mountedDetail(_ info: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(info)

            metadata(info)

            if let conflict = appState.selectedConflict {
                conflictBanner(conflict)
            }

            Divider().background(Theme.separator)

            editor(info)

            Spacer()
        }
        .padding(24)
        .task(id: info.id) { loadInitialState(for: info) }
        .onChange(of: pendingSource) { _, _ in renderPreview() }
        .onChange(of: pendingZoom) { _, _ in renderPreview() }
        .onChange(of: pendingNote) { _, newValue in
            scheduleNoteSave(info: info, note: newValue)
        }
        .sheet(isPresented: $showResetConfirm) {
            ConfirmationSheet(
                title: "Reset icon on '\(info.name)'?",
                message: "Sigil will strip the custom icon from this volume, clear the FinderInfo flag, and remove Sigil's record. Finder will show the default drive icon.",
                destructiveTitle: "Reset",
                onConfirm: {
                    showResetConfirm = false
                    Task { await performReset(info) }
                },
                onCancel: { showResetConfirm = false }
            )
        }
        .sheet(isPresented: $showForgetConfirm) {
            ConfirmationSheet(
                title: "Forget '\(info.name)'?",
                message: "Sigil will remove this volume from its memory and delete its cached icon. Any icon already on the physical volume stays — use Reset if you also want to strip it.",
                destructiveTitle: "Forget",
                onConfirm: {
                    showForgetConfirm = false
                    Task { await performForget(identity: info.identity) }
                },
                onCancel: { showForgetConfirm = false }
            )
        }
    }

    // MARK: - Remembered detail (unmounted)

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

            HStack {
                Button("Forget") { showForgetConfirm = true }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                Spacer()
                Text("Plug this volume in to edit its icon.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(24)
        .sheet(isPresented: $showForgetConfirm) {
            ConfirmationSheet(
                title: "Forget '\(record.name)'?",
                message: "Sigil will remove this volume from its memory and delete its cached icon. This does not touch the physical drive.",
                destructiveTitle: "Forget",
                onConfirm: {
                    showForgetConfirm = false
                    Task { await performForget(identity: record.identity) }
                },
                onCancel: { showForgetConfirm = false }
            )
        }
    }

    // MARK: - Subviews

    private func header(_ info: VolumeInfo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                HStack(spacing: 6) {
                    Text(info.format ?? "—")
                    Text("·")
                    Text(Self.formatBytes(info.capacityBytes))
                }
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
    }

    private func metadata(_ info: VolumeInfo) -> some View {
        HStack(spacing: 6) {
            Text(info.identity?.raw ?? "—")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text("·").foregroundStyle(Theme.tertiaryText)
            Text(info.url.path)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text("·").foregroundStyle(Theme.tertiaryText)
            Text(info.typeLabel)
                .font(.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.secondaryText)
    }

    @ViewBuilder
    private func editor(_ info: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)

            HStack(alignment: .top, spacing: 16) {
                IconDropZone(
                    pendingSource: $pendingSource,
                    previewImage: previewImage,
                    currentIcon: currentIcon
                )

                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { Task { await performApply(info) } }) {
                        if isApplying {
                            ProgressView().progressViewStyle(.circular).controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Apply").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!canApply(info))

                    Button(action: { showResetConfirm = true }) {
                        Text("Reset to default").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isRemembered(info))

                    Button(action: { showForgetConfirm = true }) {
                        Text("Forget").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .disabled(!isRemembered(info))

                    if let status = statusMessage {
                        Text(status)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .frame(width: 160, alignment: .top)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Zoom")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f×", pendingZoom))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.tertiaryText)
                    Button("Reset") { pendingZoom = 1.0 }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .disabled(pendingZoom == 1.0)
                }
                Slider(value: $pendingZoom, in: 0.5...3.0)
                    .disabled(!isZoomableSource)
            }
            .frame(maxWidth: 500)

            VStack(alignment: .leading, spacing: 4) {
                Text("Note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                TextField("e.g. Time Machine archive drive", text: $pendingNote)
                    .textFieldStyle(.roundedBorder)
                    .disabled(info.identity == nil)
            }

            if info.identity == nil {
                Text("No UUID — this volume can't be remembered.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private func conflictBanner(_ conflict: SmartSilentApplier.Outcome.Conflict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Icon conflict on remount")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            Text("This volume's current icon differs from what Sigil last wrote. Choose how to resolve:")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            HStack {
                Button("Use Sigil icon") {
                    Task { try? await appState.resolveConflictUseSigil(identity: conflict.identity) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button("Keep current") {
                    Task { try? await appState.resolveConflictKeepCurrent(identity: conflict.identity) }
                }
                .buttonStyle(.bordered)

                Button("Forget") {
                    Task { try? await appState.forget(identity: conflict.identity) }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Theme.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: - Helpers — display

    private func keyValueRow(_ key: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 72, alignment: .trailing)
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

    // MARK: - Helpers — logic

    private func isRemembered(_ info: VolumeInfo) -> Bool {
        guard let id = info.identity else { return false }
        return appState.remembered.contains { $0.identity == id }
    }

    /// The URL the editor is currently rendering from — a user-picked pending
    /// source takes precedence over the cached original.
    private var effectiveSource: URL? {
        pendingSource ?? cachedSource
    }

    /// `.icns` is already rasterized; zoom/mode do nothing. Everything else is
    /// re-renderable through ImageNormalizer.
    private var isZoomableSource: Bool {
        guard let src = effectiveSource else { return false }
        return src.pathExtension.lowercased() != "icns"
    }

    private func canApply(_ info: VolumeInfo) -> Bool {
        guard !isApplying else { return false }
        guard let id = info.identity else { return false }
        // Always apply-able when user picked a new source.
        if pendingSource != nil { return true }
        // Otherwise only if we have a re-renderable cached source AND the
        // user has moved sliders away from whatever's stored on the record.
        guard let cachedSource,
              cachedSource.pathExtension.lowercased() != "icns" else { return false }
        guard let record = appState.remembered.first(where: { $0.identity == id }) else { return false }
        return pendingMode != record.fitMode || pendingZoom != record.zoom
    }

    private func loadInitialState(for info: VolumeInfo) {
        // Load existing record's note, mode, zoom if present.
        if let id = info.identity,
           let record = appState.remembered.first(where: { $0.identity == id }) {
            pendingNote = record.note
            pendingMode = record.fitMode
            pendingZoom = record.zoom
            cachedSource = try? IconCache.sourceURL(for: id)
        } else {
            pendingNote = ""
            pendingMode = .fit
            pendingZoom = 1.0
            cachedSource = nil
        }
        pendingSource = nil
        previewImage = nil
        statusMessage = nil
        errorMessage = nil
        loadCurrentIcon(for: info)
        renderPreview()
    }

    private func loadCurrentIcon(for info: VolumeInfo) {
        guard let id = info.identity else {
            currentIcon = nil
            return
        }
        Task {
            let data = try? IconCache.loadIcns(for: id)
            let image = data.flatMap { NSImage(data: $0) }
            await MainActor.run { self.currentIcon = image }
        }
    }

    /// Fast, synchronous preview — renders from `effectiveSource` (pending or
    /// cached) at the current `pendingMode`/`pendingZoom`. Skips `iconutil`
    /// so the slider stays responsive; the full pipeline runs on Apply.
    private func renderPreview() {
        guard let source = effectiveSource else {
            previewImage = nil
            return
        }
        do {
            previewImage = try IconRenderer.preview(source: source, mode: pendingMode, zoom: pendingZoom)
            errorMessage = nil
        } catch {
            previewImage = nil
            // If the cached source is missing on disk, drop the stale reference
            // so the editor falls back cleanly to the read-only current icon
            // instead of re-erroring on every slider tick.
            if pendingSource == nil, let cached = cachedSource,
               !FileManager.default.fileExists(atPath: cached.path) {
                cachedSource = nil
                errorMessage = nil
            } else {
                errorMessage = "Couldn't render preview: \(error.localizedDescription)"
            }
        }
    }

    private func scheduleNoteSave(info: VolumeInfo, note: String) {
        guard let id = info.identity, isRemembered(info) else { return }
        noteDebounceTask?.cancel()
        noteDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? await appState.updateNote(for: id, to: note)
        }
    }

    // MARK: - Actions

    private func performApply(_ info: VolumeInfo) async {
        guard let source = effectiveSource else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = "Rendering and applying…"
        defer { isApplying = false }
        do {
            try await appState.applyIcon(source: source, mode: pendingMode, zoom: pendingZoom, to: info)
            // After apply, also push the current note if any.
            if let id = info.identity, !pendingNote.isEmpty {
                try? await appState.updateNote(for: id, to: pendingNote)
            }
            pendingSource = nil
            loadCurrentIcon(for: info)
            // Refresh cached source reference (the just-applied file was
            // copied into the cache by AppState).
            if let id = info.identity {
                cachedSource = try? IconCache.sourceURL(for: id)
            }
            renderPreview()
            statusMessage = "✓ Applied. Finder will refresh within a few seconds."
        } catch {
            errorMessage = "✗ \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private func performReset(_ info: VolumeInfo) async {
        statusMessage = "Resetting…"
        errorMessage = nil
        do {
            try await appState.resetIcon(for: info)
            pendingSource = nil
            cachedSource = nil
            previewImage = nil
            pendingNote = ""
            currentIcon = nil
            statusMessage = "✓ Reset. Finder will revert within a few seconds."
        } catch {
            errorMessage = "✗ \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private func performForget(identity: VolumeIdentity?) async {
        guard let identity else { return }
        do {
            try await appState.forget(identity: identity)
            statusMessage = "✓ Forgotten."
        } catch {
            errorMessage = "✗ \(error.localizedDescription)"
        }
    }
}
