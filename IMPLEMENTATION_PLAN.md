# Sigil v1.0 — Implementation Plan

**Created:** 2026-04-19
**Working directory:** `1-macOS/CVI/` *(retained from project codename; product ships as Sigil)*
**Source spec:** `specs/sigil-v1.md`
**Funnel position:** Plan → ready to gate into Build

---

## Plan Strategy

- **Wave-based** execution. Each wave has a single clear objective and a backpressure gate. Within a wave, tasks marked `║` are parallelizable; `→` are sequential.
- **Atomic tasks:** target ≤ 30 minutes each. Anything larger gets split.
- **Backpressure** between waves: build, lint, and (where applicable) tests must be green before advancing.
- **Subagents per `00_base.md`:** "Only 1 subagent for builds" — never run two `xcodebuild` invocations in parallel against the same scheme.

### Backpressure Chain (canonical)

Run after every wave that touches code:

```bash
xcodebuild clean -scheme Sigil -destination 'platform=macOS' && \
xcodebuild -scheme Sigil -destination 'platform=macOS' build && \
swiftlint --strict 01_Project/Sigil && \
xcodebuild test -scheme Sigil -destination 'platform=macOS'
```

If any step fails: stop, fix, rerun. Don't commit until green.

### Risk Map (Plan-time)

| Risk | Wave | Mitigation |
|------|------|------------|
| `iconutil` subprocess fails or has odd exit codes | 4 | Wave 4 ships with golden-fixture tests against a known input image |
| `setxattr` doesn't take effect on a particular volume / FS combo | 5 | Wave 5 includes integration test on a `hdiutil`-created scratch volume; readiness gate = visible icon in Finder |
| Mount events fire before app is ready (race at launch) | 3 | Coalesce: scan once on launch, subscribe; first scan handles already-mounted state, subscriber handles deltas |
| HEIC decoding requires extra image I/O setup | 4 | NSImage handles HEIC natively on macOS 14; just need correct file UTType filter in the importer |
| Finder doesn't refresh icon visibly after write | 5 | `utimes` volume root in IconApplier; document that a 1-3s lag is expected |
| Notarization fails on first attempt (hardened runtime config) | 9 | Notarize early — test the pipeline on a Wave 4 build before final shipping |

---

## Wave 0 — Project Skeleton & Repo Init

**Objective:** Empty Xcode project that builds and runs (an empty window) following the App Shell prerequisites. No app logic yet.

**Blocks:** Wave 1+

| # | Task | Time | Notes |
|---|------|------|-------|
| 0.1 | `git init` in `/Users/sim/XcodeProjects/1-macOS/Sigil/`; commit current docs/setup as initial commit | 5m | First commit on `main`; subsequent work on `feature/*` branches |
| 0.2 → | Create Xcode project: macOS App, SwiftUI lifecycle, Swift, no Core Data, no tests checkbox (we'll add a separate test target). Save to `01_Project/Sigil.xcodeproj` with product name `Sigil`, bundle ID `com.lucesumbrarum.sigil`, organization `Luces Umbrarum` | 10m | |
| 0.3 → | In Xcode target **Signing & Capabilities**: enable **Hardened Runtime** (required for notarization). Leave **App Sandbox** OFF (per distribution decision). | 5m | |
| 0.4 → | In `01_Project/Sigil/Info.plist`: add `<key>UIDesignRequiresCompatibility</key><true/>` | 3m | **Mandatory per App Shell Standard. Without this, FCPToolbarButtonStyle won't work.** |
| 0.5 → | Set **Minimum Deployments → macOS** = 14.0 in target build settings | 2m | |
| 0.6 → | Add an empty `01_Project/SigilTests/` test target, default settings | 5m | Will be populated in Waves 2/4/6 |
| 0.7 → | Create `.swiftlint.yml` at project root with default rules + `disabled_rules: [trailing_whitespace, line_length]`; install swiftlint via `brew install swiftlint` if missing | 5m | Optional but recommended; can defer if it slows the loop |
| 0.8 → | **Backpressure:** `xcodebuild build` succeeds, app launches with empty window, `xcodebuild test` runs zero tests cleanly | 5m | Commit: "Wave 0: Empty Xcode project skeleton" |

**Wave 0 Acceptance:** Empty Sigil.app launches showing a default window. Build is clean. Test target compiles.

---

## Wave 1 — App Shell (Penumbra Standard)

**Objective:** Window matches the App Shell Standard — dark, hidden title bar, HSplitView with two empty panes, FCP-styled toolbar.

**Reference:** `docs/cookbook/00-app-shell.md` (mandatory). Copy code from there directly; do not reinvent.

| # | Task | Time | Notes |
|---|------|------|-------|
| 1.1 ║ | `App/Theme.swift` — copy `Theme` struct + `ThemeManager` from cookbook (brand orange accent for now) | 10m | We may swap accent later in Wave 9 polish |
| 1.2 ║ | `App/FCPToolbarButtonStyle.swift` — copy `FCPToolbarButtonStyle` + `PaneToggleButton` from cookbook | 10m | Reusable across all toolbar buttons |
| 1.3 → | `App/SigilApp.swift` — `@main` struct, `WindowGroup { ContentView }` with `.frame(minWidth: 720, minHeight: 480)`, `.preferredColorScheme(.dark)`, `.windowStyle(.hiddenTitleBar)`, `SidebarCommands()` | 10m | |
| 1.4 → | `Views/ContentView.swift` — `HSplitView` with two placeholder panes (`SidebarView()` ~280pt min, `VolumeDetailView()` ~440pt min); `.toolbar { /* placeholder */ }`; `.toolbarRole(.editor)`; `.autosaveSplitView(named: "MainSplitView")` if cookbook helper available | 15m | |
| 1.5 → | `Views/SidebarView.swift` — placeholder Text("Sidebar"), `Theme.primaryBackground` | 5m | |
| 1.6 → | `Views/VolumeDetailView.swift` — placeholder Text("Detail"), `Theme.secondaryBackground` | 5m | |
| 1.7 → | **Backpressure:** build, launch, verify dark window, no system pill chrome on toolbar, splitter draggable. Manual visual check against cookbook screenshots. Commit: "Wave 1: App Shell Standard chrome" | 10m | |

**Wave 1 Acceptance:** Visually matches Penumbra-style dark app: hidden title bar, FCP buttons (no pills), HSplitView with two panes. No app logic yet.

---

## Wave 2 — Models + Persistence (`VolumeStore`)

**Objective:** Round-trippable JSON store for `VolumeRecord` entries, with atomic write and `.bak` fallback.

**Tests:** Unit tests live in `01_Project/SigilTests/VolumeStoreTests.swift`.

| # | Task | Time | Notes |
|---|------|------|-------|
| 2.1 ║ | `Models/VolumeIdentity.swift` — `struct VolumeIdentity: Codable, Sendable, Hashable, Equatable { let uuid: String }` | 5m | |
| 2.2 ║ | `Models/FitMode.swift` — `enum FitMode: String, Codable, Sendable, CaseIterable { case fit, fill }` | 3m | |
| 2.3 ║ | `Models/VolumeRecord.swift` — Codable struct matching the JSON layout in the spec (uuid, name, note, lastSeen, lastApplied, lastAppliedHash, fitMode, sourceFilename) | 15m | All fields immutable `let` except `note`, `lastSeen`, `lastAppliedHash`, `lastApplied`, `fitMode`, `sourceFilename`. Use `@PropertyListEncoder`-style mutation via builder if needed. |
| 2.4 → | `Services/AppPaths.swift` — locate `~/Library/Application Support/Sigil/`, `icons/`, `logs/`; create on demand via `FileManager` | 10m | |
| 2.5 → | `Services/VolumeStore.swift` — `actor VolumeStore`. Methods: `load() async throws -> [VolumeRecord]`, `save(_ records: [VolumeRecord]) async throws`, `record(for uuid: String) async -> VolumeRecord?`, `upsert(_ record: VolumeRecord) async throws`, `remove(uuid: String) async throws`. Save = write to `volumes.json.tmp` → fsync → rename over `volumes.json`; before write copy current `volumes.json` to `.bak` | 25m | |
| 2.6 → | `SigilTests/VolumeStoreTests.swift` — tests: round-trip, corrupted-primary-falls-back-to-bak, both-corrupted-starts-empty, atomic-write-survives-crash-simulation (delete tmp file mid-test), upsert idempotency | 25m | Use a per-test isolated temp directory; inject a `URL` into `VolumeStore.init`. |
| 2.7 → | **Backpressure:** `xcodebuild test` green for VolumeStoreTests. Commit: "Wave 2: VolumeStore + models" | 5m | |

**Wave 2 Acceptance:** All `VolumeStoreTests` pass. Manual `cat ~/Library/Application Support/Sigil/volumes.json` after a contrived run shows the expected JSON.

---

## Wave 3 — Volume Enumeration + Mount Watching

**Objective:** Live, accurate sidebar of currently-mounted volumes filtered by external/all toggle; updates via NSWorkspace mount events.

| # | Task | Time | Notes |
|---|------|------|-------|
| 3.1 ║ | `Services/VolumeEnumerator.swift` — `actor VolumeEnumerator`. `currentVolumes(includeSystem: Bool) -> [VolumeInfo]` using `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey], options: [.skipHiddenVolumes])`; filter out internal/boot when `!includeSystem` | 25m | Define `struct VolumeInfo: Sendable { uuid, name, url, capacityBytes, isRemovable, isInternal, format }` |
| 3.2 ║ | `Services/MountWatcher.swift` — `actor MountWatcher`. Subscribes to `NSWorkspace.shared.notificationCenter` for `.didMountNotification` + `.didUnmountNotification`; exposes an `AsyncStream<MountEvent>` where `enum MountEvent { case mounted(VolumeInfo); case unmounted(uuid: String) }` | 25m | Use `withCheckedContinuation` to bridge NotificationCenter to AsyncStream |
| 3.3 → | `App/AppState.swift` — `@MainActor @Observable final class AppState`. Holds `mounted: [VolumeInfo]`, `remembered: [VolumeRecord]`, `selectedID: String?`. Methods: `bootstrap() async` (initial scan + start watcher), `handle(_ event: MountEvent) async` | 25m | This is the orchestrator; will be extended in later waves |
| 3.4 → | Wire `AppState` into `SigilApp` via `@State` and pass via `.environment()` to ContentView | 5m | |
| 3.5 → | `Views/SidebarView.swift` — replace placeholder with two `Section`s: **Mounted** (lists `appState.mounted`) and **Remembered** (lists entries in `appState.remembered` whose uuid is NOT in `mounted`). Use `List(selection: $appState.selectedID)` | 25m | |
| 3.6 → | **Backpressure:** build, launch, plug in a USB drive → row appears in Mounted; unplug → moves to Remembered (only if previously-applied) or disappears (if never registered). Commit: "Wave 3: Live volume sidebar" | 15m | Manual smoke test required — automated test of NSWorkspace events is not worth the harness work |

**Wave 3 Acceptance:** Sidebar reflects mounted volumes live. Plugging/unplugging external drives updates rows within ~1s. No application logic for icons yet.

---

## Wave 4 — Icon Rendering Pipeline (`.icns` generation)

**Objective:** A pure pipeline that takes a source image + Fit/Fill mode and returns valid `.icns` `Data`. Testable in isolation.

| # | Task | Time | Notes |
|---|------|------|-------|
| 4.1 ║ | `Services/ImageNormalizer.swift` — `actor ImageNormalizer`. `normalize(source: URL, mode: FitMode) async throws -> NSImage` (square 1024×1024). Fit = transparent letterbox; Fill = center-crop. Validate input is decodable. | 25m | |
| 4.2 ║ | `Services/IconsetWriter.swift` — `actor IconsetWriter`. `write(image: NSImage, to iconsetDir: URL) async throws`. Renders the 8 sizes (16×1, 16×2, 32×1, 32×2, 128×1, 128×2, 256×1, 256×2, 512×1, 512×2 — note: iconutil's required filenames are documented in the spec) into PNGs via `NSBitmapImageRep` | 25m | Cookbook 17 (thread-safe rendering) — render serially in the actor since NSBitmapImageRep needs a single owner |
| 4.3 ║ | `Services/IconutilRunner.swift` — `actor IconutilRunner`. `convert(iconsetDir: URL) async throws -> Data` runs `/usr/bin/iconutil -c icns <iconsetDir>`, captures stderr, parses for errors, returns the resulting `.icns` bytes | 20m | Use `Process` + `Pipe`; 30s timeout. Cookbook 14 (subprocess + URL.path()) for the path quoting gotcha |
| 4.4 → | `Services/IconRenderer.swift` — `actor IconRenderer`. Orchestrates: ImageNormalizer → IconsetWriter (temp dir) → IconutilRunner. Cleans up temp dir in `defer` | 20m | Public API: `func render(source: URL, mode: FitMode) async throws -> Data` |
| 4.5 → | `SigilTests/IconRendererTests.swift` — fixture images at `SigilTests/Fixtures/{square_1024.png, wide_2000x800.jpg, tall_400x800.jpg, transparent.png}`. Tests: golden hash for square_1024 in fit mode (computed once, asserted thereafter); fit mode produces square output for wide/tall; fill mode crops correctly; corrupt input fails cleanly | 30m | |
| 4.6 → | **Backpressure:** test green; manually open one of the generated `.icns` files in Preview.app to eyeball quality. Commit: "Wave 4: Icon rendering pipeline" | 10m | |

**Wave 4 Acceptance:** Pipeline produces visually-correct `.icns` files for fixture images. Tests green.

---

## Wave 5 — Icon Application (the central risk)

**Objective:** Reliably apply `.icns` `Data` to a volume root such that **Finder visibly shows the new icon**, and reverse the process for Reset.

**Critical:** This wave's gate is **manual** — confirm in Finder that the icon appears.

| # | Task | Time | Notes |
|---|------|------|-------|
| 5.1 ║ | `Services/XAttr.swift` — Swift wrapper over POSIX `setxattr`/`getxattr`/`removexattr`/`listxattr`. Public surface: `set(_ name: String, value: Data, on url: URL, follow: Bool = true) throws`, `get(_ name: String, from url: URL) throws -> Data?`, `remove(_ name: String, from url: URL) throws`. Use `XATTR_NOFOLLOW` when `follow == false` | 30m | NSHipster pattern — see decisions log reference |
| 5.2 ║ | `Services/Hashing.swift` — `func sha256Hex(_ data: Data) -> String` using CryptoKit | 5m | |
| 5.3 → | `Services/IconApplier.swift` — `actor IconApplier`. Three methods: <br>• `apply(icns: Data, to volumeURL: URL) async throws -> String` (returns SHA-256 hash of written bytes). Steps: write `.VolumeIcon.icns` atomically; build 32-byte FinderInfo buffer with byte 8 = 0x04 (read existing first if present, preserve other bytes); `XAttr.set("com.apple.FinderInfo", buffer)`; `utimes` volume root to bump mtime. <br>• `reset(volumeURL: URL) async throws` — `removeItem(.VolumeIcon.icns)`; clear FinderInfo flag (byte 8 = 0x00, write back). <br>• `currentIconHash(volumeURL: URL) async -> String?` — read `.VolumeIcon.icns` if present, return SHA-256, nil if missing or unreadable | 35m | **Split into two commits if going long.** Map all errors to a `IconApplierError` enum (.readOnly, .permissionDenied, .diskFull, .notAVolume, .underlying(Error)) |
| 5.4 → | `SigilTests/IconApplierTests.swift` — integration test that creates a 10 MB scratch volume via `hdiutil create -size 10m -fs APFS -volname SigilTest /tmp/cvi-test.dmg && hdiutil attach /tmp/cvi-test.dmg`, applies an icon, asserts `.VolumeIcon.icns` exists with expected SHA, asserts FinderInfo xattr byte 8 == 0x04, then resets and asserts both are gone. Detach + delete the DMG in `defer`. Skip the test gracefully if `hdiutil` is unavailable | 35m | This is the CRITICAL integration test for the spec's central uncertainty |
| 5.5 → | **Manual smoke test:** plug in a real external drive, run a one-off Swift snippet (or temp button) that calls `IconApplier.apply(...)` with a hand-picked `.icns`. **Verify in Finder** (sidebar + Get Info) that the icon visibly appears within 5 seconds. If it doesn't, debug `utimes`/`killall Dock`/etc. before proceeding. | 30m | Commit: "Wave 5: IconApplier — verified on real volume" |

**Wave 5 Acceptance:** Both the automated integration test on a scratch DMG AND the manual smoke test on a physical external drive show the icon appearing in Finder. **Do not advance to Wave 6 until this is verified.**

---

## Wave 6 — ViewModels (Smart-Silent Orchestration)

**Objective:** Wire the services into the smart-silent reapply behavior and the per-volume detail editor logic.

| # | Task | Time | Notes |
|---|------|------|-------|
| 6.1 ║ | `ViewModels/SidebarViewModel.swift` — `@MainActor @Observable`. Combines `AppState` data into two arrays: `mountedSection` and `rememberedSection` (sorted by lastSeen desc). Selection forwarded to AppState. | 20m | |
| 6.2 ║ | `ViewModels/VolumeDetailViewModel.swift` — `@MainActor @Observable`. Holds: `selectedVolume: VolumeInfo?` or `selectedRecord: VolumeRecord?`; `pendingSource: URL?`; `pendingMode: FitMode`; `pendingNote: String`; `previewImage: NSImage?`. Methods: `import(source: URL)`, `togglePreviewMode()`, `apply()`, `reset()`, `forget()` | 30m | Debounce note edits (500ms) before persisting via VolumeStore |
| 6.3 → | `Services/SmartSilentApplier.swift` — `actor`. `func handleMount(_ info: VolumeInfo, store: VolumeStore, applier: IconApplier) async -> SilentResult` where SilentResult = `.applied(hash) / .conflict(reason) / .nothingToDo`. Reads stored record + on-disk hash; if match, calls `apply` silently and returns `.applied`; if mismatch, returns `.conflict` with details | 25m | Pure logic — no UI |
| 6.4 → | `Services/ConflictNotifier.swift` — `@MainActor`. Wraps `UNUserNotificationCenter`. Requests authorization on first use; posts notification with three actions ("Use Sigil icon", "Keep current", "Forget volume"). Action handler routes back into AppState/VolumeStore. | 30m | App needs `NSUserNotificationAlertStyle = alert` in Info.plist; add it during this task |
| 6.5 → | Integrate into `AppState.bootstrap()` and `AppState.handle(_ event:)`: on launch, scan all mounted volumes through SmartSilentApplier; on mount event, route through it; on conflict, call ConflictNotifier | 20m | |
| 6.6 → | `SigilTests/SmartSilentApplierTests.swift` — mocked store + applier; assert correct branch taken for: match / mismatch / never-seen / no-icon-on-disk | 25m | |
| 6.7 → | **Backpressure:** test green; build; commit: "Wave 6: ViewModels + smart-silent orchestration" | 10m | |

**Wave 6 Acceptance:** `SmartSilentApplierTests` pass. App launches with no behavioral regression vs Wave 5; AppState now drives ViewModels.

---

## Wave 7 — Views (User-Facing UI)

**Objective:** All UI from the spec, built on the ViewModels from Wave 6 and styled per App Shell Standard.

**Reference patterns from cookbook:** 11 (drag-drop), 05 (file dialogs), 12 (activity/progress), 09 (context menus).

| # | Task | Time | Notes |
|---|------|------|-------|
| 7.1 ║ | `Views/SidebarView.swift` — promote from Wave 3 placeholder to full styled list with two sections, custom row view (`VolumeRow`) showing icon thumbnail (32 pt), name, note (subtitle), mounted indicator dot. `.background(Theme.primaryBackground)` | 30m | |
| 7.2 ║ | `Views/VolumeRow.swift` — extracted reusable row | 15m | |
| 7.3 ║ | `Views/EmptyStateView.swift` — illustration (SF Symbol `externaldrive.badge.plus` at 80pt), headline + body text per spec | 15m | |
| 7.4 ║ | `Views/IconDropZone.swift` — `.onDrop(of: [.fileURL], …)` + `.fileImporter` for click-to-pick. Allowed UTTypes: `.png`, `.jpeg`, `.heic`, `.icns`. On drop → call `viewModel.import(source:)`. Visual: dashed rounded rect, 200×200, hover state | 30m | Cookbook 11 |
| 7.5 ║ | `Views/PreviewCanvas.swift` — renders `viewModel.previewImage` at 256×256 with subtle drop shadow and rounded corners (matches Finder rendering) | 15m | |
| 7.6 → | `Views/VolumeDetailView.swift` — full layout: header (`PreviewCanvas` + name + capacity + format + UUID monospaced), `IconDropZone` + Browse button row, Fit/Fill picker (segmented), note `TextField` (debounced binding), action button row (Apply primary, Reset bordered, Forget destructive) | 45m | **Split into 7.6a (layout) and 7.6b (action wiring) if needed** |
| 7.7 → | `Views/ConfirmationSheets.swift` — `ResetConfirmationSheet`, `ForgetConfirmationSheet`, `ConflictResolutionSheet` (the latter is fallback if user invokes from sidebar context menu, not just notification) | 25m | |
| 7.8 → | `Views/Toolbar.swift` — `ToolbarItemGroup(.primaryAction)` with: "Show all volumes" toggle (`PaneToggleButton`), "About" button. Apply `FCPToolbarButtonStyle(isOn: ...)`. | 20m | |
| 7.9 → | Wire toolbar into `ContentView`, ensure `.toolbarRole(.editor)` still set | 5m | |
| 7.10 → | **Backpressure:** build, manual walk-through of every spec acceptance criterion (use spec checklist as a script). Commit: "Wave 7: Full UI" | 30m | |

**Wave 7 Acceptance:** Every "Must Have (P0)" and "Should Have (P1)" acceptance criterion in the spec is reachable through the UI. Visual style matches cookbook. No round capsule buttons anywhere.

---

## Wave 8 — Logging, Error Surfaces, Edge Cases

**Objective:** Wire `os.Logger` throughout, surface every error from the spec to the user, handle edge cases.

| # | Task | Time | Notes |
|---|------|------|-------|
| 8.1 ║ | `Logging/Log.swift` — `enum Log { static let mount = Logger(subsystem: "com.lucesumbrarum.sigil", category: "mount"); … io / render / ui }` | 10m | |
| 8.2 ║ | Add log calls at the four high-value points: every mount/unmount event, every `IconApplier.apply` outcome, every `VolumeStore.save` outcome, every user action | 25m | Don't log secrets; do log volume names (visible to user anyway) |
| 8.3 ║ | `Views/Errors/ErrorAlerts.swift` — view modifier `.cviErrorAlert(error: $appState.lastError)`. Maps `IconApplierError` and `VolumeStoreError` cases to user-friendly messages per spec error rows | 25m | Read-only / EPERM / ENOSPC / decode-failed each get a dedicated message |
| 8.4 ║ | Disk-space preflight in `IconApplier.apply` — before write, check volume free space ≥ 1 MB via `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`. If insufficient, throw `.diskFull` BEFORE writing. | 15m | Cookbook 29 |
| 8.5 → | `volumes.json` corruption recovery: on `VolumeStore.load` failure, attempt `.bak`; if both fail, present a non-blocking sheet "Couldn't read your saved volumes — starting fresh" with an "Import volumes.json…" button (file picker) | 25m | |
| 8.6 → | Handle volumes with no UUID: in `VolumeEnumerator`, if `.volumeUUIDStringKey` is nil, surface as `VolumeInfo` with `uuid = nil`; in `VolumeDetailView`, gray out Apply/Forget with tooltip "This volume has no UUID and can't be remembered." | 20m | |
| 8.7 → | **Backpressure:** walk through every spec "Edge Cases" and "Error States" row; verify the right alert/UI appears. Commit: "Wave 8: Logging + error surfaces + edge cases" | 30m | |

**Wave 8 Acceptance:** Every spec acceptance criterion (Must, Should, Edge, Error) is covered. `os.Logger` output visible in Console.app filtered by subsystem.

---

## Wave 9 — Polish, App Icon, Notarization, Ship

**Objective:** Notarized DMG ready for GitHub Releases.

| # | Task | Time | Notes |
|---|------|------|-------|
| 9.1 ║ | App icon design in Affinity Designer: `02_Design/Sigil-Icon.afdesign`. Suggested motif: stylized HDD/SSD with a paintbrush or color swatches. Export as `02_Design/Exports/AppIcon.appiconset/` | 60m+ | Open Question O.2 — see below |
| 9.2 ║ | Add the `AppIcon.appiconset` to `01_Project/Sigil/Assets.xcassets/` | 5m | |
| 9.3 ║ | `README.md` at project root: pitch, screenshots, install steps, requirements (macOS 14+), known limitations (Finder lag), donation link | 30m | |
| 9.4 ║ | `LICENSE` — MIT recommended (matches "free + donationware" ethos) | 5m | |
| 9.5 → | `04_Exports/SHIPPING.md` — document the notarization workflow: `xcodebuild archive` → export Developer ID app → `notarytool submit … --wait` → `stapler staple`. Include a copy-paste script. | 30m | |
| 9.6 → | First notarization dry run on a Wave 5+ build to surface any signing/runtime issues early | 30m | Apple Developer account required ($99/yr); confirm user has it before this task |
| 9.7 → | Build Release (`-configuration Release`), notarize, staple, package as DMG (use `create-dmg` brew tool or hand-roll), drop in `04_Exports/Sigil-1.0.0.dmg` | 30m | |
| 9.8 → | Tag `v1.0.0` in git; create GitHub Release with DMG attached, paste the README's "What's new" into release notes | 15m | |

**Wave 9 Acceptance:** A signed, notarized DMG downloads from GitHub Releases, opens cleanly on a fresh Mac without Gatekeeper warnings, and the app works end-to-end on the user flow described in the spec.

---

## Open Questions (must be resolved before specific waves)

| ID | Question | Blocks | Suggested default |
|----|----------|--------|-------------------|
| ~~O.1~~ | ~~Bundle identifier?~~ | — | **Resolved 2026-04-19:** `com.lucesumbrarum.sigil`. Product name: Sigil. |
| O.2 | App icon design starting point? | Wave 9 only | Brainstorm in Affinity later; doesn't block Build phase |
| O.3 | Apple Developer account in hand? | Wave 9 only | If no, app can still ship with Gatekeeper warning; just not "trusted" |
| O.4 | swiftlint installed locally? | Wave 0.7 (optional) | Skip if not installed; not load-bearing |

---

## Time Budget (rough)

| Wave | Tasks | Time (est.) |
|------|-------|-------------|
| 0 | 8 | ~50m |
| 1 | 7 | ~65m |
| 2 | 7 | ~88m |
| 3 | 6 | ~120m |
| 4 | 6 | ~140m |
| 5 | 5 | **~165m** ← critical |
| 6 | 7 | ~150m |
| 7 | 10 | ~250m |
| 8 | 7 | ~150m |
| 9 | 8 | ~205m (excluding icon design) |

**Total Build phase (Waves 0-8):** ~17 build-hours. Realistic for a focused weekend (one day building + one day polish + ship).

**Wave 9 design + notarization:** ~3-4 hours if you have an icon idea, much more if you're starting from a blank canvas.

---

## Per-Wave Commit Convention

```
Wave N: <one-line summary>

- <bullet 1>
- <bullet 2>

Co-authored-by: Claude
```

Branch strategy: one feature branch per wave (`feature/wave-N-<name>`), merge to `main` after backpressure passes. Tag `wave-N-done` on `main` after each merge for easy rollback.

---

## How to Execute This Plan

Per `docs/00_base.md`, use `/execute` for wave-based parallel execution with fresh subagent contexts. For each wave:

1. Read this plan + the relevant spec section.
2. Read the cookbook references (Wave 1 → cookbook 00; Wave 4 → 14, 17; Wave 7 → 11, 05, 12, 09; Wave 8 → 29).
3. Execute parallel tasks (`║`) via subagents; sequential (`→`) in main thread.
4. Run backpressure chain.
5. Commit, update `PROJECT_STATE.md`, create session log, advance.

If a wave reveals a flaw in the plan, regenerate (don't patch) — see `00_base.md` "Regeneration Philosophy".
