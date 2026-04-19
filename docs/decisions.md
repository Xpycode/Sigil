# Decisions Log — CVI

This file tracks the **WHY** behind technical and design decisions. Append-only, newest at top.

---

## Template

### YYYY-MM-DD — [Decision Title]

**Context:** What situation prompted this decision?

**Options Considered:**
1. **Option A** — pros/cons
2. **Option B** — pros/cons
3. **Option C** — pros/cons

**Decision:** What we chose.

**Rationale:** Why this won.

**Trade-offs accepted:** What we give up.

**Revisit if:** Conditions that would make us reconsider.

---

## Decisions

### 2026-04-19 — Product name: Sigil; bundle ID: `com.lucesumbrarum.sigil`

**Context:** Working codename was "CVI" (Custom Volume Icons) — descriptive but generic. User has personal Apple Developer namespace `com.lucesumbrarum` (Latin: "lights of shadows" / chiaroscuro). Brainstorm produced six candidates spanning literal (DriveIcon), heraldic (Crest, Marque), Latin (Lares, Tessera), and English-evocative (Sigil, Imprint).

**Options Considered:**
1. **Keep "CVI"** — three-letter acronym, unclaimed but forgettable. No brand presence.
2. **Sigil** — personal mark/seal denoting ownership; two syllables; exact metaphor for the app's function.
3. **Imprint** — English verb+noun; precise and pronounceable; mildly common.
4. **Lares** — Roman household guardian spirits; pairs poetically with the namespace; obscure pronunciation.
5. **Tessera** — Roman ID token / mosaic tile; beautiful but three syllables.
6. **Crest** — heraldic mark; simple but generic.

**Decision:** **Sigil**. Bundle ID `com.lucesumbrarum.sigil`. Organization name "Luces Umbrarum".

**Rationale:**
- Two syllables, single noun — matches the most-loved Mac utility naming convention (Bartender, Magnet, Bear, Hazel, Tot).
- Metaphor maps exactly to the app: a sigil is a personal mark you stamp on something to claim it.
- Pairs cleanly with `com.lucesumbrarum.sigil` — both Latin/heraldic in feel without redundancy.
- No major Mac app currently named Sigil (the EPUB editor "Sigil" is a different category — open-source ebook tool, no brand collision in the utility/file-management space).

**Trade-offs accepted:**
- Slight occult/mystical connotation. Acceptable; in context it reads as heraldic, not arcane.
- Working directory `1-macOS/CVI/` retained to avoid path churn in the Directions docs. All product-facing strings and the Xcode product itself ship as "Sigil".

**Side effects of this decision:**
- App Support directory: `~/Library/Application Support/Sigil/` (not CVI)
- Logger subsystem: `com.lucesumbrarum.sigil` (not com.cvi.app)
- Xcode product / scheme / source folder / test target: `Sigil` / `SigilTests`
- README, About window, all UI: "Sigil"

---

### 2026-04-19 — Icon-application mechanism: direct two-step write (NOT `NSWorkspace.setIcon`)

**Context:** During /plan research, discovered that `NSWorkspace.shared.setIcon(_:forFile:options:)` — the obvious-looking single API call we initially planned to use — has been broken for volume roots since **macOS 13.1**. The Cocoa call writes the `.VolumeIcon.icns` file but silently fails to set the `kHasCustomIcon` flag in `com.apple.FinderInfo`. Without the flag, Finder ignores the icon entirely. Confirmed by:
- The `fileicon` CLI README explicitly notes the failure (mklement0/fileicon).
- Multiple GitHub issues across icon-management tools (e.g., `create-dmg` issue #57).
- Apple Community / dev forums report the same since Ventura.

**Options Considered:**
1. **Use `NSWorkspace.setIcon` and pray** — rejected; documented to fail on the exact thing we're shipping.
2. **AppleScript bridge** (osascript with NSWorkspace) — same underlying API, same failure.
3. **Direct two-step write** — write `.VolumeIcon.icns` ourselves with `Data.write(to:options:.atomic)`; set `com.apple.FinderInfo` via `setxattr(2)` to a 32-byte buffer with byte 8 = `0x04`. Optionally `utimes` the volume root to refresh Finder. Used by every working modern volume-icon tool.
4. **Spawn `SetFile -a C`** (Carbon) — works but `SetFile` is removed from modern Xcode command-line tools and unavailable to most users. Brittle.

**Decision:** Option 3 — direct two-step write via `Data.write` + thin `setxattr` Swift wrapper.

**Rationale:**
- Only path that reliably works on macOS 13+, including the macOS 14 minimum we're targeting.
- Both Foundation (`Data.write`) and POSIX (`setxattr`) are stable, documented, available without entitlements.
- `setxattr` Swift wrapper is ~30 lines (POSIX C interop pattern documented at NSHipster).
- Atomicity: we write `.VolumeIcon.icns` atomically (temp + rename), then set xattr; if xattr fails after write, we delete the file to avoid an orphan.
- Reset is symmetric: `removeItem(.VolumeIcon.icns)` + `removexattr(com.apple.FinderInfo)` (or write zero buffer if xattr already had unrelated bytes — read-modify-write).

**Trade-offs accepted:**
- We're maintaining a tiny POSIX wrapper. Acceptable; ~30 lines, well-tested pattern.
- Finder cache may take 1-3 seconds to pick up the new icon. We `utimes` the volume root to nudge it; if that's not enough we accept the brief lag (avoiding `killall Finder` — too disruptive for a casual utility).
- If a user runs CVI alongside another tool that also fights for the icon, last writer wins. Not a real concern.

**Revisit if:** Apple fixes `NSWorkspace.setIcon` for volumes in a future macOS release (would simplify the IconApplier service significantly).

**References:**
- [fileicon README](https://github.com/mklement0/fileicon) — documents the failure
- [NSHipster — Extended File Attributes](https://nshipster.com/extended-file-attributes/) — Swift `setxattr` pattern
- [Eclectic Light — Custom Finder icons](https://eclecticlight.co/2023/03/04/custom-finder-icons-resources-and-mac-os-history/) — modern storage mechanism (xattr + .icns)

---

### 2026-04-19 — UI shell + background behavior (Tier 1)

**Context:** CVI's "auto-reapply on remount" feature requires *something* to be running when a volume mounts. Three architectural tiers were considered (window-only, menu-bar companion, launch-at-login). User's instinct was to question whether background watching is actually needed.

**Decision:** **Tier 1 — plain window app, no menu bar, no launch-at-login.**

- Standard SwiftUI window app following the App Shell Standard (HSplitView, FCPToolbarButtonStyle, `.windowStyle(.hiddenTitleBar)`, `.preferredColorScheme(.dark)`, `.toolbarRole(.editor)`, Theme struct — see `docs/cookbook/00-app-shell.md`).
- Mount-watcher (`NSWorkspace.didMountNotification`) is registered only while the window is alive — used for live UI updates during a session.
- Auto-reapply triggers at: **(i) app launch** (scan all currently-mounted remembered volumes), **(ii) any mount event while CVI is open**.
- If user plugs in a remembered drive while CVI is closed → Finder shows the default icon → next time CVI is opened, it re-applies. The previously-applied `.VolumeIcon.icns` typically persists on the drive itself across mount cycles, so this gap is rarely visible in practice.
- **Sidebar layout:** two sections — **Mounted** (default expanded, mounted volumes only) and **Remembered** (collapsible, unmounted entries). Filter: external volumes only by default; toolbar toggle "Show all" reveals boot / system / DMGs.
- **Empty state:** welcome message + single CTA ("Mount an external drive to get started") with a small illustration. No tutorial overlay.

**Rationale:**
- The killer feature isn't background magic — it's *persistence of icon assignments across reformats and machines*. That value works fine with an opened-on-demand model.
- Tier 1 saves an estimated full day of work (no `MenuBarExtra` lifecycle, no `SMAppService.mainApp` registration, no Settings surface, no helper-running indicator).
- Truly weekend-shippable. Tier 2/3 can be added in v1.1 if user feedback demands it.

**Trade-offs accepted:**
- If a remembered drive is plugged in with Sigil closed and the on-disk `.VolumeIcon.icns` was wiped externally (e.g., reformatted on Windows), the user sees the default icon until they next open CVI. This is the only meaningful UX cost; it's acceptable for v1.

**Revisit if:** User reports indicate "I keep forgetting to open CVI" or want truly always-on behavior.

---

### 2026-04-19 — Persistence, volume identity, auto-reapply policy

**Context:** Define how CVI remembers volumes across mount cycles, what it does when a remembered volume reappears, and where data lives on disk.

**Decision:**

- **Volume identity:** UUID-first, read from `URLResourceKey.volumeUUIDStringKey`. No fallback to `(label + size)` — too risky (two blank exFAT cards collide). If a volume reformats, it gets a new UUID and looks brand-new to CVI; the old entry persists as an orphan in the unmounted list until the user explicitly Forgets it.
- **Volume scope:** External volumes only by default (filter out boot, system, recovery, mounted DMGs). Include a "Show all volumes" toggle in the toolbar / preferences for power users.
- **Auto-reapply on remount — "smart silent" pattern:**
  - **Default path:** when a remembered volume mounts AND its current `.VolumeIcon.icns` matches the SHA-256 hash CVI stored at last-apply time, **silently re-apply** with no UI. Maximum magic, no annoyance.
  - **Conflict path:** when the on-disk hash differs (user changed the icon elsewhere, or the file was deleted), **do NOT auto-apply**. Post a user notification with three actions: **"Use CVI icon"** (overwrite + update memory), **"Keep current"** (update CVI memory to match disk), **"Forget volume"**.
  - **Stored hash field:** `lastAppliedHash` (SHA-256 of the `.VolumeIcon.icns` we wrote).
- **Orphan policy:** Never auto-delete. Orphans persist in the "Unmounted" section indefinitely until user clicks Forget. Each entry shows `lastSeen` date.
- **Storage layout:**
  ```
  ~/Library/Application Support/CVI/
  ├── volumes.json    ← single source of truth
  │     [{ uuid, name, note, lastSeen, lastApplied, lastAppliedHash, sourceRef, fitMode }]
  ├── icons/
  │   ├── {uuid}.src.{png|icns}   ← user-provided source (for re-render/edit)
  │   └── {uuid}.icns             ← rendered output (cached for fast re-apply)
  └── logs/
      └── cvi.log                 ← rolling diagnostic log
  ```
- **JSON, not SQLite:** at the scale of this app (dozens to maybe a few hundred volumes per user), JSON is simpler, debuggable in any text editor, easy to back up. SQLite is overkill.
- **No CloudKit / sync:** out of scope for v1. (Mentioned in case anyone asks: would require entitlement gymnastics and isn't worth it for a free single-machine utility.)

**Rationale:**
- "Smart silent" is the unique value prop: feels magical 99% of the time, won't surprise-overwrite you the 1% of the time it would matter.
- UUID-only identity is clean and avoids ghost-collisions; the cost (orphan entries on reformat) is paid manually by the user, which is correct because data loss is worse than housekeeping.
- Storing both source and rendered `.icns` is a modest disk cost (~1MB per volume worst case) but enables Fit/Fill re-toggling and resolution upgrades without re-importing.

**Trade-offs accepted:**
- Hash-checking adds ~50ms per mount event. Imperceptible.
- Orphans accumulate over years. Acceptable; user can prune via UI.
- JSON file corruption (e.g., crash mid-write) could lose all memory. Mitigation: atomic write via temp-file + rename, plus a single rolling backup `volumes.json.bak`.

**Revisit if:** volume count per user exceeds ~500 (move to SQLite), or sync demand emerges.

---

### 2026-04-19 — Icon sources & UX (v1 scope)

**Context:** Define what users can use as an icon source and what UI surface ships in v1 vs. later.

**Decision:**
- **v1 sources:** image file (PNG/JPEG/HEIC) and existing `.icns` file. Both via picker AND drag-and-drop.
- **v1.1 (future):** SF Symbols with color tint.
- **Deferred indefinitely:** emoji picker, drag-from-app, icon library/stash, batch.
- **Non-square images:** offer **Fit** (auto-pad to square with transparent background) and **Fill** (auto-crop center) as a toggle in the preview. Default = Fit (less destructive).
- **Reset to default:** mandatory button — strips both `.VolumeIcon.icns` from the volume AND removes the entry from CVI's memory.
- **Preview:** show a rendered preview at icon size (e.g., 128×128 in the detail pane) before the user clicks Apply. If technically painful, fall back to apply-immediately. Since we render the `.icns` ourselves, the preview is essentially free.
- **Per-volume note:** free-text field, ~140 chars, shown in the volume list and detail pane. Especially valuable for unmounted volumes you need to identify later.

**Rationale:**
- Image + `.icns` covers 95% of cases for a v1. Holding `.icns` support is critical because that's what power users with existing icon libraries already have.
- Fit + Fill toggle is the standard photo-import pattern (CSS `object-fit: contain` vs `cover`); users understand it instantly.
- Notes turn the unmounted list from "anonymous UUIDs" into a usable inventory — small UI cost, big payoff.

**Trade-offs accepted:**
- No emoji/SF Symbols in v1 = less viral demo appeal. Acceptable; ship first, iterate.
- Storing the source image (not just the rendered .icns) increases storage cost slightly but allows re-rendering and editing later.

**Revisit if:** v1 ships and demand for SF Symbols / emoji is high.

---

### 2026-04-19 — Distribution: GitHub direct download, no Mac App Store (yet)

**Context:** Need to choose a distribution channel before locking in sandbox/entitlement architecture. MAS forces sandboxing; direct download allows non-sandboxed binaries.

**Options Considered:**
1. **Mac App Store only** — easiest install, auto-update, but mandatory sandbox. Writing `.VolumeIcon.icns` to a volume root would require per-volume `NSOpenPanel` permission + security-scoped bookmarks. Significant UX friction for the core action.
2. **GitHub direct download (notarized DMG)** — non-sandboxed, can write to volume roots freely (subject to filesystem perms). Requires Apple Developer ID + notarization for Gatekeeper. No auto-update built-in (would need Sparkle).
3. **Both** — maximum reach, double the maintenance, two builds with different capabilities.

**Decision:** Option 2 — GitHub direct download, notarized DMG, non-sandboxed.

**Rationale:**
- The core action (write to a mounted volume's root) becomes trivial without the sandbox.
- Donationware fits GitHub Releases naturally; MAS doesn't allow tip jars on free apps anyway.
- Weekend-project scope can't absorb the per-volume bookmark UX that sandboxing would require.
- Can add MAS later as a separate, sandboxed build if demand appears.

**Trade-offs accepted:**
- Need an Apple Developer account ($99/yr) for notarization. Without it, users see the Gatekeeper warning.
- No automatic update channel out of the box (revisit Sparkle if iterating beyond v1.0).
- Smaller discovery surface than MAS.

**Revisit if:** Project outgrows weekend scope and demand exists for MAS distribution.

---

### 2026-04-19 — Min macOS 14 (Sonoma)

**Context:** Choose deployment target. Newer = more SwiftUI features, less back-compat code; older = bigger user base.

**Decision:** macOS 14.0 minimum.

**Rationale:**
- Lets us use `@Observable` macro (no `ObservableObject` boilerplate), modern `NavigationSplitView`/`HSplitView` polish, `Inspector`, `ContentUnavailableView`, etc.
- macOS 14 is two releases old by April 2026 — adoption is high enough for a niche utility.
- Weekend scope benefits from skipping conditional-availability checks.

**Trade-offs accepted:** Excludes users still on macOS 13 / 12. Acceptable for a free, niche tool.

---

### 2026-04-19 — Audience, pricing, scope

**Decision:**
- **Audience:** Public release (not personal use only).
- **Pricing:** Free; donationware via GitHub Sponsors / Buy Me a Coffee link in About.
- **Scope:** Weekend project — single-shot v1.0, no auto-update infrastructure, aggressive feature pruning to ship.

**Rationale:** Public release means we need an icon, About window, README, and notarization — but pricing-free + weekend scope means no payment plumbing, no licensing, no telemetry.

**Trade-offs accepted:** No way to push fixes without users redownloading. Manual update notification on launch (optional, lightweight) is the lazy alternative to Sparkle.


