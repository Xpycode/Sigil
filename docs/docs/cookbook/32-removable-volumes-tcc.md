# Removable Volumes TCC Declaration

**Use when:** a non-sandboxed macOS app writes to the **root** of removable
volumes (USB sticks, SD cards, CFExpress cards, external SSDs) and ships on
macOS 13 (Ventura) or later. Without an `NSRemovableVolumesUsageDescription`
in the Info.plist, every such write **silently fails with `EACCES`** and the
user has no path to grant access from inside or outside the app.

**Source:** `1-macOS/Sigil/01_Project/Sigil/Info.plist`,
`Services/IconApplier.swift`. Triggered by Sigil v1.0.0 shipping without the
key — every user attempting to apply an icon to a removable volume got a
"Permission denied" error and no prompt.

---

## What changed in macOS 13

Before Ventura, non-sandboxed apps had implicit access to write anywhere
the user could. Apple tightened TCC (Transparency, Consent, and Control)
to gate writes to **removable-volume roots** behind an explicit user
permission, mirroring the long-standing protection for Documents/Desktop/
Downloads/iCloud Drive.

The gate behavior:

1. App tries to write to `/Volumes/<removable>/something`.
2. macOS checks the running process's TCC status for the **Removable
   Volumes** capability.
3. If never decided AND the app's Info.plist contains
   `NSRemovableVolumesUsageDescription`: macOS shows a system prompt with
   that description string. User clicks Allow → write proceeds. User
   clicks Don't Allow → `EACCES`.
4. If never decided AND the Info.plist has NO usage-description string:
   **macOS denies silently with `EACCES`** — no prompt, no System Settings
   entry to flip on, the user is permanently locked out from inside the
   app.

The silent denial in step 4 is the trap. The app gets a Cocoa
`fileWriteNoPermission` error, which sounds like a regular file-system
permission issue, but the user can't fix it in Finder Get Info or `chmod` —
TCC overrides everything below it.

## The fix: declare the key

In `Info.plist`:

```xml
<key>NSRemovableVolumesUsageDescription</key>
<string>To apply the icon you chose, Sigil writes a small icon file to the drive's root so it appears in Finder.</string>
```

That's the entire fix. macOS ships you back to step 3.

## Writing the description string

The string is **permanent UX** — it appears in:

1. The macOS prompt the first time the user triggers a removable-volume
   write.
2. System Settings → Privacy & Security → Files & Folders → \<App\> →
   Removable Volumes (forever, with no way to edit it post-install).

It also appears in App Store Review when relevant. Apple rejects vague
strings (`"For app functionality"`); concrete strings tied to user-visible
actions sail through.

### The formula

> "To do **\<the action the user just initiated\>**,
> \<App\> writes **\<concrete description of what gets written\>**
> so **\<observable user-facing benefit\>**."

Sigil's string follows this exactly:

> "To apply the icon you chose, Sigil writes a small icon file to the
> drive's root so it appears in Finder."

| Slot | Content | Why |
|---|---|---|
| Action the user just initiated | "to apply the icon you chose" | Mirrors the verb on the button they just pressed. Reads as a direct response to their action, not a separate request. |
| What gets written | "a small icon file to the drive's root" | Concrete and bounded. "A file at the root" is a well-defined, minimal disclosure — not "files," not "data," not "storage." |
| User-facing benefit | "so it appears in Finder" | Closes the loop. Connects the permission request to what the user actually wanted. |

### Don't write

- ❌ `"<App> needs permission to..."` — redundant with the OS chrome line
  ("`<App>` would like to access files on a removable volume.") that
  precedes your string.
- ❌ Vague: `"For full app functionality"`, `"To enable features"`. Apple
  rejects.
- ❌ Threatening: `"<App> will not work without this access"`. Apple rejects.
- ❌ Long: anything over ~150 characters gets truncated with the buttons
  pushed off-screen. Aim for one tight sentence.

## Improve the error message too

When the user does tap Don't Allow (or revokes later in System Settings),
the next write returns `CocoaError.fileWriteNoPermission`. Don't surface
the raw "Permission denied" — that's not actionable. Point them at the
exact System Settings pane:

```swift
case .permissionDenied(let url):
    return "Can't write to '\(url.lastPathComponent)' — Sigil needs Removable Volumes access. Open System Settings → Privacy & Security → Files & Folders."
```

## Diagnostic: is this the bug you're hitting?

If your non-sandboxed app:

- Targets macOS 13+ as deployment minimum, AND
- Writes to anything under `/Volumes/<not-the-boot-volume>/`, AND
- Gets `EACCES` / `Errno 13` / Cocoa `fileWriteNoPermission` for files on
  removable volumes, AND
- The user reports never seeing a permission prompt, AND
- System Settings → Privacy & Security → Files & Folders → \<your app\>
  shows no "Removable Volumes" toggle…

…you're missing `NSRemovableVolumesUsageDescription`. Add the key, rebuild,
re-sign. The next time the user triggers a removable-volume write, they'll
get the prompt.

## Test environment caveat

This bug is **invisible during development if you only test on local
volumes** — the boot volume, internal SSDs, and APFS containers don't go
through the Removable Volumes TCC bucket. Sigil v1.0.0 shipped without
the key because every dev test wrote to APFS volumes; the bug only
surfaced on the first real-user external-card test.

**Action item for any volume-touching feature:** smoke-test on at least
one APFS internal AND one non-APFS removable volume (an SD card or USB
stick) before tagging a release. Same gap caught Sigil's
`volumeAvailableCapacityForImportantUsageKey` bug (cookbook 29) — both
failures were "tested only on the dev's preferred filesystem."

## Existing-user upgrade path

If you ship a v1.0.x update that adds the key for the first time:

- TCC keys per code-signing identity. The fact that the v1.0.0 binary
  triggered (silent) denials doesn't poison the v1.0.1 grant. The first
  removable-volume write after upgrading will trigger a fresh prompt.
- Worth calling out in release notes so users aren't confused by the new
  prompt: *"First-run permission prompt on macOS 13+: \<App\> now requests
  Removable Volumes access. Required by macOS — earlier versions silently
  failed without it."*

## Related

- `cookbook/30-color-managed-icon-pipeline.md` — once you can write, write
  the right bytes.
- `cookbook/31-finder-volume-icon-cache.md` — once you've written the
  right bytes, get Finder to actually show them.
- `cookbook/29-disk-space-preflight.md` — the other "APFS-only assumption"
  gap (both bugs go away with the same "test on a non-APFS volume" rule).
