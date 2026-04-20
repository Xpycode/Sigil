# Sigil v1.0 Specification

**Status:** Approved → Plan complete (`IMPLEMENTATION_PLAN.md`) → ready for Build
**Product:** Sigil  *(working codename was CVI — Custom Volume Icons)*
**Bundle ID:** `com.lucesumbrarum.sigil`
**Working directory:** `1-macOS/Sigil/`
**Created:** 2026-04-19
**Last updated:** 2026-04-19

---

## Problem Statement

### What problem does this solve?

macOS Finder allows users to set a custom volume icon (Get Info → paste image), but the icon is stored as a hidden `.VolumeIcon.icns` file at the root of the volume itself. This means the icon is **lost** when the volume is reformatted, used on another machine that strips it, or simply never assigned in the first place. There is no Finder UI for managing icons across many volumes, and no way to "queue" an icon for a drive that isn't currently plugged in.

### Who has this problem?

People who manage many external drives — photographers (SD cards, backup SSDs), video editors (project drives, media drives), archivists, and developers with multiple bootable / scratch / data drives. They want consistent, memorable icons across their inventory.

### How do they solve it today?

- Manually paste icons via Finder Get Info, one drive at a time.
- Re-do the work each time a drive is reformatted or used on another Mac.
- Cope with a sea of identical generic external-drive icons.

---

## Proposed Solution

### One-Liner

A small macOS window app that assigns custom icons to external volumes and remembers icons for unmounted volumes, re-applying automatically when the volume returns.

### Key Capabilities

1. **Apply** a custom icon to a mounted volume from a PNG / JPEG / HEIC image or an existing `.icns` file.
2. **Remember** the icon-to-volume mapping in a local store keyed by volume UUID.
3. **Smart-silent re-apply** when a remembered volume is mounted while Sigil is open: silently apply if the on-disk icon matches what Sigil last wrote, otherwise post a notification with conflict-resolution actions.
4. **Browse** all known volumes — currently mounted (with icon status) and remembered-but-unmounted.
5. **Reset** to default icon (strip `.VolumeIcon.icns` and remove from memory).
6. **Forget** a remembered volume (delete entry + cached files).
7. **Annotate** each volume with a free-text note (e.g., "Daily editing drive").

### User Flow — First Use

1. User opens Sigil for the first time. Detail pane shows welcome empty-state.
2. User plugs in an external SSD. The Mounted section in the sidebar gains a row.
3. User clicks the row. Detail pane shows volume info and an icon-drop area.
4. User drags `photos.png` onto the drop area. Preview renders at 256×256.
5. User toggles Fit/Fill (default Fit), optionally types a note, clicks **Apply**.
6. Sigil generates `.icns`, writes it to the volume, sets the `kHasCustomIcon` flag, persists the mapping. Finder updates within ~1 second.

### User Flow — Returning Use

1. User opens Sigil. App scans currently-mounted volumes and processes any pending re-applies (smart-silent).
2. Sidebar shows Mounted (live) + Remembered (unmounted) sections.
3. User can edit any volume's icon, note, or reset/forget it.

### User Flow — Auto Re-apply (Sigil open)

1. User plugs in a remembered drive while Sigil is running.
2. Sigil receives `NSWorkspace.didMountNotification`.
3. If on-disk icon hash == stored hash (or no on-disk icon yet), Sigil silently writes the stored icon. Sidebar updates.
4. If on-disk icon hash != stored hash, Sigil posts a `UNUserNotification` with three actions:
   - **Use Sigil icon** — overwrite the on-disk icon, update stored hash.
   - **Keep current** — update Sigil memory to match the new on-disk hash; do not overwrite.
   - **Forget volume** — delete Sigil's entry and cached files.

---

## Acceptance Criteria

> Given/When/Then format. Each row maps to one or more tests during `/plan`.

### Must Have (P0) — Core Apply / Remember

- [ ] Given a mounted external volume with no custom icon, when user drops a PNG and clicks **Apply**, then `.VolumeIcon.icns` exists at the volume root, **and** Finder displays the new icon, **and** Sigil's `volumes.json` contains a new entry keyed by the volume's UUID.
- [ ] Given a mounted volume with an `.icns` file dropped, when user clicks **Apply**, then the `.icns` is written to the volume root verbatim (no re-rendering), **and** Finder displays the new icon.
- [ ] Given a remembered volume mounts while Sigil is open **and** on-disk hash matches stored `lastAppliedHash`, when the mount event fires, then the icon is silently re-applied with no UI prompt **and** sidebar updates the row to "mounted".
- [ ] Given a remembered volume mounts while Sigil is open **and** on-disk hash differs from stored hash (or `.VolumeIcon.icns` is missing), when the mount event fires, then a `UNUserNotification` appears with three actions (Use Sigil icon / Keep current / Forget) **and** the on-disk icon is **not** overwritten until the user picks an action.
- [ ] Given app launches with N remembered volumes already mounted, when the launch scan completes, then each is processed per the smart-silent rule above within 2 seconds total for N ≤ 50.
- [ ] Given a user clicks **Reset to Default**, when confirmed in a sheet, then `.VolumeIcon.icns` is removed from the volume **and** `kHasCustomIcon` is cleared **and** Sigil's memory entry is deleted **and** cached files in `~/Library/Application Support/Sigil/icons/{uuid}.*` are deleted.
- [ ] Given a user clicks **Forget** on a remembered (unmounted or mounted) volume, when confirmed in a sheet, then the entry is removed from `volumes.json` **and** all `~/Library/Application Support/Sigil/icons/{uuid}.*` files are deleted **but** any `.VolumeIcon.icns` already on the physical volume is **not** touched.

### Must Have (P0) — Image Handling

- [ ] Given a non-square image is selected with **Fit** mode, when previewed, then the result is square with transparent padding around the longest edge fitted into the icon canvas.
- [ ] Given a non-square image is selected with **Fill** mode, when previewed, then the result is center-cropped to a square.
- [ ] Given any source image, when **Apply** is clicked, then a multi-resolution `.icns` is generated containing 16, 32, 64, 128, 256, 512, and 1024 px representations.
- [ ] Given a source image is imported, when Sigil persists it, then the original file is copied to `~/Library/Application Support/Sigil/icons/{uuid}.src.{ext}` so subsequent Fit/Fill toggles can re-render without re-asking the user.

### Must Have (P0) — Per-volume Note

- [ ] Given a user types in the per-volume note field, when the user leaves the field **or** 500 ms of inactivity passes, then the note is persisted to `volumes.json` and visible on the corresponding sidebar row.
- [ ] Given a remembered (unmounted) volume row is displayed in the sidebar, when rendered, then it shows the volume's last-known name, the user's note (if any), and `lastSeen` date.

### Should Have (P1) — Sidebar / Filters

- [ ] Given external volumes are mounted, when Sigil launches, then the sidebar's **Mounted** section lists them all (excluding boot, system, recovery, and mounted DMGs by default).
- [ ] Given remembered-but-unmounted volumes exist, when Sigil launches, then the **Remembered** section in the sidebar lists them in `lastSeen` descending order.
- [ ] Given the user toggles the toolbar "Show all" control on, when toggled, then boot / system / DMG volumes also appear in the Mounted section.
- [ ] Given the user resizes the window, when the sidebar reaches its minimum width (160 pt) or detail reaches its minimum (320 pt), then the splitter stops shrinking the constrained pane.

### Should Have (P1) — Empty / First-Run

- [ ] Given the app is freshly installed and no volumes are remembered, when Sigil launches, then the detail pane shows a welcome empty-state with the message "Mount an external drive to get started" and a small illustration.
- [ ] Given an empty `volumes.json` and no external volumes are currently mounted, when Sigil launches, then the sidebar shows an "All clear" empty placeholder under both sections.

### Edge Cases

- [ ] Given a volume reports no UUID via `URLResourceKey.volumeUUIDStringKey` (extremely rare; e.g., some ramdisks), when Sigil tries to register it, then the volume appears in the sidebar but the Apply / Forget actions are disabled with a tooltip explanation.
- [ ] Given `volumes.json` is unreadable (corrupted JSON, missing) on launch, when Sigil starts, then it falls back to `volumes.json.bak` and shows a non-fatal warning sheet; if both are unreadable, it starts with an empty store and offers to import.
- [ ] Given a write to `volumes.json` fails (disk full, permission), when persistence is attempted, then the operation is retried once after 250 ms; if still failing, an error sheet appears with the OS error and the in-memory state is preserved until next try.
- [ ] Given the cached `{uuid}.src.{ext}` is missing from app support but the entry exists in `volumes.json`, when the user toggles Fit/Fill, then Sigil re-renders from the cached `{uuid}.icns` (if available) at reduced quality, or shows a "Source missing — re-import" message.

### Error States

- [ ] Given the volume root is read-only (e.g., HFS+ mounted read-only, locked DMG), when **Apply** is clicked, then an alert appears reading "Can't write to '[Volume Name]': read-only filesystem" and no memory entry is created.
- [ ] Given write fails with `EPERM`/`EACCES` (permission), when **Apply** is clicked, then an alert appears with the OS error and a hint to check Disk Utility or volume mount options.
- [ ] Given write fails with `ENOSPC` (volume full), when **Apply** is clicked, then an alert appears reading "Volume '[X]' is full — free at least 1 MB and try again". *(See cookbook 29-disk-space-preflight.md for prevention.)*
- [ ] Given the source image cannot be decoded as a valid bitmap (corrupted file, unsupported format), when imported, then the import is rejected with a clear error and no `.icns` is generated.

### Performance

- [ ] Given 50 remembered volumes with cached thumbnails, when Sigil launches, then the sidebar renders within 300 ms on a 2024-era Apple-silicon Mac.
- [ ] Given a 2000 × 2000 px source image, when **Apply** is clicked, then `.icns` rendering completes in under 500 ms on a 2024-era Apple-silicon Mac.
- [ ] Given a mount event for a remembered volume, when smart-silent is triggered, then the apply path completes (hash check + write) within 200 ms.

---

## Technical Considerations

### Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI with `@Observable` (no `ObservableObject`)
- **Min target:** macOS 14.0 (Sonoma)
- **Hashing:** `CryptoKit` SHA-256
- **Logging:** `os.Logger`, subsystem `com.lucesumbrarum.sigil`, categories: `mount`, `io`, `render`, `ui`
- **Notifications:** `UserNotifications` (`UNUserNotificationCenter`) for the conflict-resolution prompt

### Apple APIs

- **Volume identity:** `URL.resourceValues(forKeys: [.volumeUUIDStringKey])`
- **Volume metadata:** `.volumeNameKey`, `.volumeTotalCapacityKey`, `.volumeIsRemovableKey`, `.volumeIsInternalKey`, `.volumeLocalizedFormatDescriptionKey`
- **Mount events:** `NSWorkspace.shared.notificationCenter.addObserver(...)` for `.didMountNotification` and `.didUnmountNotification`
- **Mounted volumes enumeration:** `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:options:)`
- **Icon application — two-step write (REQUIRED, see decisions log 2026-04-19):**
  1. Write `.VolumeIcon.icns` directly to `{volumeURL}/.VolumeIcon.icns` with atomic `Data.write(to:options:.atomic)`.
  2. Set the `com.apple.FinderInfo` extended attribute on the volume root via `setxattr(2)` to a 32-byte buffer with byte 8 = `0x04` (`kHasCustomIcon` flag at the FolderInfo flags position).
  3. Optional: `utimes` the volume root to nudge Finder to re-read (avoid `killall Finder` — too disruptive).
  - **Why not `NSWorkspace.shared.setIcon(_:forFile:options:)`:** since macOS 13.1, that API silently writes `.VolumeIcon.icns` but **fails to set the FinderInfo flag** on volume mountpoints, so Finder ignores the icon. Confirmed by the `fileicon` CLI maintainers and reproduced across user reports.
- **Icon reset — two-step:** delete `.VolumeIcon.icns`; clear FinderInfo flag (write 32-byte zero buffer OR `removexattr`).
- **`.icns` generation — `iconutil` subprocess:** render `NSImage` at the eight required sizes (16, 32, 64, 128, 256, 512, 1024 px and their `@2x` variants) into a temp `.iconset/` directory using `NSBitmapImageRep`, then invoke `/usr/bin/iconutil -c icns input.iconset` via `Process`. Reliable, ships with macOS, no third-party dependency. *(Pure-Swift `.icns` writer rejected — adds 200+ lines for marginal benefit; `iconutil` works fine outside the sandbox, which we're not in.)*

### Architecture

Per `docs/00_base.md` and `docs/cookbook/00-app-shell.md`:

- **ViewModels:** `@MainActor @Observable` final classes
- **Services:** `actor` types (e.g., `VolumeStore`, `IconRenderer`, `MountWatcher`)
- **Models:** `struct`, `Codable`, `Sendable` (e.g., `VolumeRecord`, `VolumeIdentity`)
- **Views:** SwiftUI structs, App Shell Standard

Proposed module layout (to be confirmed in `/plan`):

```
01_Project/Sigil/
├── App/
│   ├── SigilApp.swift              ← @main, scenePhase, init services
│   ├── AppState.swift            ← @MainActor @Observable root state
│   └── Theme.swift               ← Theme struct (per App Shell Standard)
├── Models/
│   ├── VolumeRecord.swift        ← Persisted entry (Codable)
│   ├── VolumeIdentity.swift      ← UUID wrapper + equality
│   └── FitMode.swift             ← enum { fit, fill }
├── Services/
│   ├── VolumeStore.swift         ← actor, JSON persistence, atomic write + .bak
│   ├── MountWatcher.swift        ← actor, NSWorkspace observer
│   ├── VolumeEnumerator.swift    ← enumerates current mounts, filters
│   ├── IconRenderer.swift        ← actor, image → .icns generation
│   └── IconApplier.swift         ← actor, write .icns + set Finder flag, hashing
├── ViewModels/
│   ├── SidebarViewModel.swift
│   └── VolumeDetailViewModel.swift
├── Views/
│   ├── ContentView.swift         ← HSplitView root
│   ├── SidebarView.swift
│   ├── VolumeDetailView.swift
│   ├── EmptyStateView.swift
│   ├── IconDropZone.swift
│   ├── PreviewCanvas.swift
│   └── Toolbar.swift             ← uses FCPToolbarButtonStyle
├── Resources/
│   ├── Assets.xcassets/
│   └── Info.plist
└── Logging/
    └── Log.swift                 ← os.Logger wrappers
```

### Persistence Format (`volumes.json`)

```json
[
  {
    "uuid": "11111111-2222-3333-4444-555555555555",
    "name": "Photos SSD",
    "note": "Daily editing drive",
    "lastSeen": "2026-04-19T14:30:00Z",
    "lastApplied": "2026-04-18T09:15:00Z",
    "lastAppliedHash": "sha256:e3b0c44298fc1c149afbf4c8996fb924...",
    "fitMode": "fit",
    "sourceFilename": "photos.png"
  }
]
```

Atomic write strategy: write to `volumes.json.tmp`, fsync, rename over `volumes.json`. Keep one rolling `volumes.json.bak` from before the write.

### Security & Permissions

- **Non-sandboxed.** No entitlements file needed beyond standard `Hardened Runtime` for notarization.
- **No privileged operations.** Volume root writes are user-permission. Boot volume writes will fail with EPERM (and we filter boot out anyway).
- **Notarization:** Required. Apple Developer ID + `notarytool` workflow. *(Setup deferred to shipping phase.)*

### Logging Categories (initial)

| Category | What gets logged |
|----------|------------------|
| `mount` | Mount/unmount events received, volume URL + UUID |
| `io` | Read/write of `volumes.json`, `.VolumeIcon.icns`, source images |
| `render` | Image → `.icns` pipeline timing, errors |
| `ui` | User-initiated actions (Apply, Reset, Forget) |

---

## Out of Scope (v1.0)

Explicitly excluded — these are documented so they don't drift back in:

- **SF Symbol icons** (planned for v1.1)
- **Emoji icons**
- **Drag-from-app** to "borrow" another item's icon
- **Background process / launch-at-login** (Tier 2/3 — see decisions log)
- **Menu bar icon / `MenuBarExtra`**
- **iCloud / multi-machine sync**
- **Auto-update / Sparkle** (manual download from GitHub Releases for v1.0)
- **Localization** (English only)
- **Mac App Store distribution**
- **Light theme** (dark only per App Shell Standard)
- **Batch operations** (apply same icon to multiple volumes at once)
- **Icon library / favorites** within Sigil
- **Time-Machine-style icon history**
- **AppleScript / Shortcuts integration**
- **CLI companion**

---

## Open Questions

| Question | Status | Answer |
|----------|--------|--------|
| Use `iconutil` subprocess or pure-Swift `.icns` writer? | Resolved | `iconutil` subprocess. See "Icon application" above. |
| `NSWorkspace.setIcon` vs direct two-step write? | Resolved | Direct two-step write (research finding 2026-04-19). |
| Notarization tooling: manual `notarytool` or fastlane? | Open | Defer to shipping phase (Wave 9). |
| Bundle identifier? | Resolved | `com.lucesumbrarum.sigil` (organization: Luces Umbrarum). |
| App icon design (the icon for Sigil itself)? | Open — needed for Wave 9 only | Affinity Designer source in `02_Design/`, generated `AppIcon.appiconset` in `02_Design/Exports/` |
| `iconutil` is sandbox-incompatible — confirm we're staying non-sandboxed forever for v1? | Resolved | Yes, see distribution decision 2026-04-19 |
| Finder cache refresh strategy after writing? | Resolved | `utimes` on volume root after writing; avoid `killall Finder`. |

---

## Related

- **Decisions:** `docs/decisions.md` — five entries from 2026-04-19 covering distribution, target, sources, persistence, UI shell
- **Pattern Cookbook:** `docs/cookbook/00-app-shell.md` (mandatory), `docs/cookbook/29-disk-space-preflight.md`, `docs/cookbook/11-drag-drop.md`
- **macOS reference:** `docs/22_macos-platform.md` for platform gotchas (sandboxing, entitlements, bookmarks — mostly inapplicable since we're non-sandboxed)
- **Session log:** `docs/sessions/2026-04-19.md`

---

## Spec Review Checklist

Before gating into `/plan`:

- [x] Problem statement is clear (not solution-focused)
- [x] Acceptance criteria are testable (Given/When/Then)
- [x] Edge cases are documented
- [x] Out of scope is explicit
- [x] Open questions are resolved or noted as deferred
- [x] Technical considerations cover dependencies
- [x] Security implications considered (notarization, non-sandboxed write surface)
