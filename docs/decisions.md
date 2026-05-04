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

### 2026-05-04 — Reset / Forget must reset zoom + mode too

**Context:** `performReset` and `performForget` cleared most editor state
(`pendingSource`, `cachedSource`, `previewImage`, `pendingNote`,
`currentIcon`) but left `pendingZoom` and `pendingMode` at whatever values
the last Apply had set them to. After a Reset on a 3.00× icon, the slider
stayed pinned at 3.00×. Reads as "Reset didn't fully reset."

**Decision:** Both functions now also `pendingZoom = 1.0` and
`pendingMode = .fit`. Trivial change; brings the editor to a clean,
consistent post-Reset / post-Forget state matching what the user sees
when they first select a fresh volume.

**Affected:** `01_Project/Sigil/Views/VolumeDetailView.swift`
(`performReset`, `performForget`).

---

### 2026-05-04 — Finder cache invalidation, round 2: notify both volume URL AND icns file URL

**Context:** Round-1 fix (pair `utimes` with `NSWorkspace.noteFileSystemChanged`
on the volume URL) helped on first applies but didn't reliably refresh
Finder on overwrites. Definitive diagnosis came from a `shasum` comparison
between Sigil's saved icns at `~/Library/Application Support/Sigil/icons/<UUID>.icns`
and the on-disk `/Volumes/<vol>/.VolumeIcon.icns` — they matched bit-for-bit.
So the bytes were correct on disk; Finder was simply serving a cached icon
from a previous apply.

Investigation showed Finder's volume-icon cache lives in **two** buckets,
keyed independently by:
- the volume URL (the directory containing the icns), and
- the icns file URL itself (Finder treats the leading-dot hidden path as
  its own cache entry).

Notifying only the volume URL invalidates the first bucket but leaves the
second populated; Finder serves from whichever it consults first.

**Decision:** Bump mtime AND post `noteFileSystemChanged` for **both** the
volume URL and the icns URL. Same calls, twice each, against two paths.

Reference implementations in `iconset` and `fileicon` (popular custom-icon
CLIs) do the same dual-path dance — confirmed reading their source.

**Trade-offs accepted:** Two extra syscalls per apply (one `utimes`, one
notification). Negligible cost; runs once per Apply, not per render tier.

**Revisit if:** Even dual notification proves insufficient on some volumes
or future macOS releases. The next escalation is toggling the
`kHasCustomIcon` FinderInfo flag (clear → set) — that forces Finder to
re-evaluate "does this volume have a custom icon" entirely, not just
"what icon." More invasive (extra xattr write); kept in reserve.

**Affected:** `01_Project/Sigil/Services/IconApplier.swift`
(`touchVolume` — notify on both `url.path` and
`url.appendingPathComponent(iconFilename).path`).

---

### 2026-05-04 — Reset / Forget must reset zoom + mode too

**Context:** v1.0.1 testing surfaced that re-applying an icon (with a new
zoom value) to a previously-iconned volume succeeded end-to-end on disk —
the saved `.VolumeIcon.icns` correctly contained the zoomed content (verified
via Quick Look) — but Finder continued to show the *previously-applied*
volume icon. The user's natural reading was "the zoom slider doesn't work."
Real bug: Finder's volume-icon cache wasn't being invalidated when the icns
was overwritten in place.

`IconApplier.touchVolume` already called `utimes(volumeURL.path, nil)` to
nudge mtime/atime. That works on a *first* apply (no prior icon → Finder
reads fresh) but is documented to be insufficient when **overwriting an
existing file in place** — Finder's cache is keyed by inode + mtime + size,
and a same-size atomic-replace can slip past it.

**Options Considered:**
1. **Pair `utimes` with `NSWorkspace.shared.noteFileSystemChanged(path)`** —
   the canonical "I just changed this, please re-look at it now" push hint.
   Used by both popular custom-icon CLIs (`fileicon`, `iconset`). Apple
   discourages it for general filesystem watching (FSEvents replaced FNNotify
   there) but it remains the right tool for this specific push case.
2. **Force-remove the old icns before writing the new one** — generates a
   guaranteed-different inode. Reliable invalidation. Downside: brief window
   where the volume has no `.VolumeIcon.icns`, during which Finder might
   render the default drive icon and the user sees a flicker.
3. **Use AppleScript `tell application "Finder" to update <volume>`** —
   most heavy-handed; spawns or wakes Finder, requires Automation permission,
   defeats the unobtrusiveness Sigil aims for.

**Decision:** Option 1. Single line added after `utimes`. No flicker, no new
permissions, no subprocess overhead, no behavior change on the first apply
(both calls are no-op-equivalent when nothing was cached).

**Rationale:** The whole reason `touchVolume` exists is to invalidate
Finder's perception of the volume icon. `utimes` is the polite-but-quiet
hint; `noteFileSystemChanged` is the explicit one. Together they cover both
the "first apply" path (where utimes alone works) and the "overwrite" path
(where it doesn't). Same call shape, same place in the code, near-zero
cognitive overhead for future readers (extensive comment explains the why).

**Trade-offs accepted:** `noteFileSystemChanged` is documented as
"discouraged" for general filesystem watching, but the docs explicitly note
that the alternative (FSEvents) is for *receiving* notifications, not
*sending* them. For the push case, this API is still the supported path.

**Revisit if:** Apple removes `noteFileSystemChanged` entirely (no signs of
deprecation as of macOS 15) or if Finder's cache invalidation behavior
changes again. Both unlikely.

**Affected:** `01_Project/Sigil/Services/IconApplier.swift` (added
`import AppKit` and one line in `touchVolume`).

**Sources:** Apple Developer Documentation — [`NSWorkspace.noteFileSystemChanged`](https://developer.apple.com/documentation/appkit/nsworkspace/1579268-notefilesystemchanged),
plus reference implementations in [`fileicon`](https://github.com/mklement0/fileicon)
and [`iconset`](https://github.com/tale/iconset).

---

### 2026-05-04 — Drop Forget from mounted detail; keep on Remembered only

**Context:** A user-perspective audit raised that on a mounted volume, the
Forget button is **strictly redundant** with Reset:

- Reset (`AppState.resetIcon`): strips `.VolumeIcon.icns` from the drive,
  clears the FinderInfo flag, removes the record, deletes the cache.
- Forget (`AppState.forget`): removes the record, deletes the cache. Leaves
  the on-drive icon intact.

Reset is a **strict superset** of Forget when a volume is mounted. Two buttons
side-by-side that look like they "do almost the same thing" are textbook UX
confusion — and Sigil is a small focused tool where every visible control
should pay rent.

**Options Considered:**
1. **Drop Forget from the mounted detail view; keep it only on Remembered
   (unmounted) volumes** — eliminates the side-by-side redundancy.
   Functional necessity preserved (you can't Reset an unmounted disk because
   Reset writes to it; Remembered volumes still need *some* way to be pruned
   from the list). Cross-Mac power-user workflow ("apply icon, hand card to
   colleague, stop tracking it on my Mac without erasing the icon") becomes
   a two-step: eject the card, then Forget from the Remembered section.
2. **Rename both buttons** — e.g. Reset → "Remove icon", Forget → "Remove
   from list" — to make the distinction clearer. Doesn't actually solve the
   redundancy on mounted volumes, just papers over it.
3. **Keep both as-is** — status quo. Costs the user a moment of "wait,
   what's the difference" every time they're about to remove an icon.

**Decision:** Option 1. Mounted detail now shows: Apply · Reset to default.
Remembered detail still shows: Forget. Reset's confirmation copy now points
at the cross-Mac workflow as discoverable text:

> "...remove Sigil's record. Finder will show the default drive icon.
>
> If you want to keep the icon on the drive but stop Sigil tracking it,
> eject the volume first, then use Forget from the Remembered list."

**Rationale:** The cross-Mac case is real but niche; users who care about
that semantic now have it documented in the Reset confirmation rather than
needing to discover it by comparing two button captions. The everyday user
sees one obvious destructive action ("Reset to default") that does what its
name says. The Remembered view still has Forget because functionally it
*must* — you cannot Reset a disk that is not currently writeable.

**Trade-offs accepted:** One extra step (eject) for the cross-Mac workflow.
Acceptable; rare flow, and the eject is itself a meaningful safety boundary
(physically separating the card from your Mac before declaring "I'm done
with this here").

**Revisit if:** A noticeable fraction of users want to declutter Sigil's
Remembered list while volumes are still mounted. (No evidence of this so
far; if it surfaces, a Cmd-modifier on Reset, or a small ⋯ menu, can
re-introduce Forget without putting the redundant button back in the
default flow.)

**Affected:** `01_Project/Sigil/Views/VolumeDetailView.swift` (removed the
Forget button + its `.sheet` wiring from the mounted detail; enriched the
Reset confirmation copy with the eject-first hint).

---

### 2026-05-04 — Icon pipeline: explicit sRGB CGContext (not `.deviceRGB` / `NSImage(size:flipped:)`)

**Context:** v1.0.1 smoke test surfaced a colour-shift bug: an Angelbird AV PRO
SE CFexpress B silver-card source rendered as visibly gold/warm in the saved
`.VolumeIcon.icns` (verified in Quick Look). Same source had rendered correctly
silver in earlier sessions. Two root causes in the icon pipeline:

1. **`ImageNormalizer.normalize`** built its 1024×1024 canvas with
   `NSImage(size:flipped:drawingHandler:)`. Per Apple Developer Forums thread
   728687 ("How To Resize An Image and Retain Wide Color Gamut"), drawing
   handlers create a context with **unspecified** colour space — the
   destination ends up tagged with whatever the implicit context happens to
   be, which on Sonoma+ wide-gamut displays defaults to a P3-like profile.
2. **`IconsetWriter.renderPNG`** allocated its `NSBitmapImageRep` with
   `colorSpaceName: .deviceRGB`. `.deviceRGB` is **device-dependent**: on a
   Display P3 Mac (every M-series MacBook Pro, every Studio Display), this
   resolves to a P3 destination. Drawing an sRGB-tagged source into a P3
   destination triggers a colour-space conversion that warps neutral
   metallics — silver → gold is the characteristic artifact.

Compounded, the pipeline tagged its PNGs with the device profile, embedded
them in the icns, and Finder rendered the P3-encoded silver back on a P3
display as visibly warm. The bug was latent on every wide-gamut Mac since
shipping; it just hadn't surfaced because the dev's earlier smoke tests had
landed on a colour profile that happened to round-trip cleanly.

**Options Considered:**
1. **Explicit sRGB throughout the pipeline** — build both contexts via
   `CGContext(... space: CGColorSpace(name: CGColorSpace.sRGB), ...)` and
   wrap in `NSGraphicsContext` for AppKit drawing. Apple's recommended
   pattern (Developer Forums thread 679891). Source images get colour-mapped
   into sRGB once at normalize time; PNGs are tagged sRGB; Finder renders
   sRGB; round-trip is stable.
2. **Explicit Display P3 throughout** — preserve wide gamut for sources that
   have it. Marginal benefit (icons are small UI surfaces), and risks
   looking off when the user moves the volume to a non-P3 display.
3. **Use `NSColorSpaceName.calibratedRGB`** — generic device-independent RGB.
   Closer to sRGB than `.deviceRGB` but still imprecise; depends on AppKit's
   internal mapping and could shift again across macOS releases.

**Decision:** Option 1. Explicit sRGB in both places via `CGContext` →
`NSGraphicsContext(cgContext:flipped:)` → AppKit drawing → `cgContext.makeImage()` →
`NSBitmapImageRep(cgImage:)`. ICC profile is unambiguous, deterministic, and
matches what Finder/Dock/`iconutil` expect from icon assets.

**Rationale:** Volume icons aren't wide-gamut content — they're small UI
glyphs displayed at 16–1024 px. sRGB covers all the colour Finder will ever
display them in. The explicit `CGColorSpace.sRGB` context removes any
ambiguity about destination tagging, so the same source produces the same
output regardless of which display the dev (or user) happens to have plugged
in. The fix lives at the two pipeline endpoints (normalize + per-tier PNG
encode), so it covers both the in-app preview and the on-disk icns.

**Trade-offs accepted:** Wide-gamut sources (Display P3 PNGs from photo apps)
get clipped to sRGB gamut at normalize time. Saturated reds/greens lose ~5%
chroma. Acceptable for UI iconography.

**Revisit if:** Apple introduces a new ICNS-with-color-profile container
format, or Finder starts rendering volume icons in wide-gamut contexts where
P3 would visibly improve fidelity. (Neither has happened as of macOS 15.)

**Affected:** `01_Project/Sigil/Services/ImageNormalizer.swift` (replaced
`NSImage(size:flipped:drawingHandler:)` with explicit-sRGB CGContext path,
added `.contextAllocationFailed` error case),
`01_Project/Sigil/Services/IconsetWriter.swift` (replaced `.deviceRGB`
NSBitmapImageRep with explicit-sRGB CGContext path, added
`.contextAllocationFailed` error case).

**Sources:** Apple Developer Forums [thread 728687](https://developer.apple.com/forums/thread/728687)
("How To Resize An Image and Retain Wide Color Gamut"), [thread 679891](https://developer.apple.com/forums/thread/679891)
("How to create RGBA CGColorSpace / bitmap CGContext").

---

### 2026-05-04 — Detail header shows actual icon (not SF Symbol placeholder)

**Context:** `VolumeDetailView` rendered its 56-pt header icon as a hardcoded
SF Symbol (`externaldrive.fill` for mounted, `externaldrive` for remembered)
even when the volume had a real custom icon applied. Since the sidebar rows
already showed real cached thumbnails, the detail view felt inconsistent
with itself ("the small one knows but the big one doesn't").

**Decision:** Header now shows `currentIcon` (loaded from `IconCache` via
`loadCurrentIcon(for:)`) when available; falls back to the SF Symbol when
no cached icon exists.

**Live preview vs committed state:** The header reflects only `currentIcon`
(the committed on-disk icon), not `previewImage` (the live editor preview).
This keeps the header as a quiet visual confirmation of "this is what's on
the drive" while the canvas remains the editing surface. Watching both
animate during a slider drag would be busy.

**Both code paths:** Mounted and remembered headers both updated. The
remembered path also gained a `.task(id: record.identity.raw)` that calls
the now-shared `loadCurrentIcon(for: VolumeIdentity?)` helper, since the
disconnected-volume detail view never loaded the icon before.

**Affected:** `01_Project/Sigil/Views/VolumeDetailView.swift` (extracted
`headerIcon` / `rememberedHeaderIcon` view-builders, refactored
`loadCurrentIcon` to share between mounted and remembered paths, wired
remembered's `.task(id:)` loader).

---

### 2026-05-04 — `performForget` resets editor state to match `performReset`

**Context:** Tapping Forget left the editor in a half-forgotten state —
canvas kept showing the just-rendered preview, note text persisted, etc.,
even though the volume had been removed from `appState.remembered` and the
header had reset to the generic drive icon. `performReset` already did the
right cleanup; `performForget` only updated `statusMessage`.

**Decision:** `performForget` now mirrors `performReset`'s editor reset
(clears `pendingSource`, `cachedSource`, `previewImage`, `pendingNote`,
`currentIcon`). The only difference between Reset and Forget remains the
underlying service call — Reset strips the icon from disk, Forget just
removes Sigil's record.

**Affected:** `01_Project/Sigil/Views/VolumeDetailView.swift`
(`performForget`).

---

### 2026-05-04 — Removable-volume TCC: declare `NSRemovableVolumesUsageDescription`

**Context:** After fixing the disk-space preflight (entry below), the apply path
surfaced a second failure: macOS returned `EACCES` from `Data.write` to the
ExFAT volume root. Cause: since macOS 13 Ventura, even non-sandboxed apps need
TCC permission to write to removable-volume roots. Without
`NSRemovableVolumesUsageDescription` in `Info.plist`, macOS refuses the write
**without ever showing a prompt** — the user has no way to grant access from
inside the app, and the System Settings → Files & Folders pane shows no Sigil
entry to flip on.

This was missed during initial development for the same reason as the
disk-space bug: all dev testing happened on local APFS volumes
(`~/Library/Application Support/Sigil/`, internal Macintosh HD), where the
Removable Volumes TCC bucket doesn't apply.

**Options Considered:**
1. **Add `NSRemovableVolumesUsageDescription` with a clear copy string** — the
   correct, Apple-blessed path. User gets a one-time prompt on first apply;
   System Settings shows Sigil under Files & Folders → Removable Volumes
   forever after.
2. **Add a runtime check that detects EACCES and pops a custom dialog
   explaining how to fix it** — works around the missing Info.plist key but
   still requires the user to leave the app and toggle a Settings switch
   manually. Strictly worse UX.
3. **Switch to a privileged helper / SMAppService model** — overkill; would
   require codesigning a helper, install/remove ceremony, persistent launchd
   job. Wildly disproportionate for "write a 1MB icon file."

**Decision:** Option 1. Added the key with the string:
> "To apply the icon you chose, Sigil writes a small icon file to the drive's
> root so it appears in Finder."

Chose this wording (combo of two earlier candidates AB1/AB3) because it (a)
mirrors the action the user just took ("apply"), (b) explains *what* gets
written so the request feels honest and bounded, and (c) avoids the redundant
"needs permission to" framing that the OS chrome already provides.

Also improved `IconApplier.Error.permissionDenied`'s message to point users at
the exact System Settings pane, since some users will tap "Don't Allow" on the
prompt and need to course-correct without guesswork.

**Rationale:** The string is permanent UX — it appears in the macOS prompt
forever and in the System Settings pane forever — so it's worth getting right.
Apple rejects vague strings ("for app functionality"); concrete strings tied
to user-visible actions sail through review.

**Trade-offs accepted:** v1.0.0 users who already installed will see a fresh
permission prompt on first apply after upgrading. This is the correct system
behavior but should be called out in v1.0.1 release notes.

**Revisit if:** Apple changes TCC behavior again (Sequoia / macOS 16 has
already tightened removable-volume rules once more — worth monitoring).

**Affected:** `01_Project/Sigil/Info.plist` (added key, bumped version to
1.0.1 / build 2), `01_Project/Sigil/Services/IconApplier.swift` (improved
permissionDenied error copy).

**Note for later cleanup:** `Sigil.xcodeproj/project.pbxproj` already had
`MARKETING_VERSION = 1.0.1` and `CURRENT_PROJECT_VERSION = 101` set, but they
were inert because `GENERATE_INFOPLIST_FILE = NO` and Info.plist used literal
strings rather than `$(MARKETING_VERSION)` substitution. Consider switching
Info.plist to substitution form so version lives in one place — or just
delete the dormant pbxproj entries.

---

### 2026-05-04 — Disk-space preflight: dual-key probe, skip-on-unknown

**Context:** v1.0.0 user reported that applying an icon to an ExFAT CFExpress B card
failed with "Volume 'XH2S-512' is full — need 1.2 MB, have Zero KB." The card was
nowhere near full. Root cause: `IconApplier.freeSpaceBytes` queried only
`volumeAvailableCapacityForImportantUsageKey`, which is APFS-specific and returns
`0` (not nil) on ExFAT/FAT32/HFS+. Since Sigil targets *external volumes* — and
external volumes are overwhelmingly ExFAT — this silently broke the core flow on
the most common real-world case.

**Options Considered:**
1. **Use only the legacy `volumeAvailableCapacityKey`** — works everywhere but
   ignores APFS purgeable storage, so preflight could falsely reject on APFS
   volumes that Finder shows as having space.
2. **Try ForImportantUsage first, fall back to legacy when it returns nil OR 0** —
   correct for both filesystems; matches what Finder reports on APFS and gives a
   real number on ExFAT.
3. **Keep the APFS-only key but skip the preflight entirely when unavailable** —
   defers all errors to ENOSPC at write time. Worse UX: user sees a generic
   write failure with the partially-written `.VolumeIcon.icns` left on disk.

**Decision:** Option 2. Dual-key with `> 0` guard on the APFS key. When **both**
keys return nil/0, return nil and let the preflight skip the check (the `if let
available` short-circuits) — i.e. **skip-on-unknown, attempt the write**.

**Rationale:** Better to attempt and surface a real ENOSPC than to falsely block
when measurement fails. The atomic write in step 1 means a true ENOSPC leaves
nothing partial on the volume; only the FinderInfo step writes more bytes, and
that's <100 bytes, so the slack-byte budget covers it.

**Trade-offs accepted:** On a genuinely-full unmeasurable volume, the user sees
a kernel ENOSPC error from `Data.write` instead of our friendlier "Volume is
full" message. Acceptable — that case is vanishingly rare (every macOS-supported
filesystem reports capacity), and the kernel message is still actionable.

**Revisit if:** We add support for unusual filesystems (NTFS via paragon,
network mounts, FUSE) where capacity reporting is genuinely unreliable. At that
point, consider a small probe-write strategy.

**Affected:** `01_Project/Sigil/Services/IconApplier.swift` (freeSpaceBytes),
`docs/docs/cookbook/29-disk-space-preflight.md` (DiskSpace.availableCapacity
example had the same flaw — fixed inline + added explicit non-APFS warning).

---

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


