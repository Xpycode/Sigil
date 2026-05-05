# Finder Volume-Icon Cache Invalidation

**Use when:** an app writes `.VolumeIcon.icns` to a volume root and needs
Finder to refresh its volume thumbnail. Or more generally: any time you've
*changed* a file that Finder displays an icon for, and you want the change
to be visible in Finder without a logout / `killall Finder` / eject-remount.

**Source:** `1-macOS/Sigil/01_Project/Sigil/Services/IconApplier.swift`. The
honest result: **none of the techniques below reliably refresh Finder on
*overwrite*.** First-time applies (no prior cached icon for the path) refresh
fine; overwriting an existing icon is where Finder's icon-services cache wins.

This entry documents what does and doesn't work so the next person doesn't
re-run the same four experiments.

---

## The honest summary

| Technique | First apply | Overwrite |
|---|---|---|
| `utimes(path, nil)` on volume root | ✅ usually | 🟡 sometimes |
| `+ NSWorkspace.noteFileSystemChanged` on volume URL | ✅ | 🟡 sometimes |
| `+ noteFileSystemChanged` on the icns file URL too | ✅ | 🟡 sometimes |
| `+ FinderInfo `kHasCustomIcon` flag toggle (clear → set) | ✅ | ❌ doesn't help |
| Eject + remount the volume | ✅ | ✅ always |
| `killall Finder` | ✅ | ✅ always |

**Implementation recommendation:** do all four push hints (rows 1-4). They're
cheap, correct hygiene, and the first-apply path benefits. But **don't
promise users that re-applying an icon will refresh in Finder** — surface a
"may need to eject/remount" hint or remove the surface that exposes the
problem (as Sigil did with the zoom slider).

## Pattern: belt-and-braces invalidation

```swift
import AppKit

private static let iconFilename = ".VolumeIcon.icns"

private static func touchVolume(_ url: URL) {
    let iconURL = url.appendingPathComponent(iconFilename)

    // 1. Bump mtime/atime on both the volume root and the icns file.
    //    Finder's cache is keyed on (inode, mtime, size). A same-size atomic
    //    rewrite produces a new inode but same mtime+size; bumping mtime
    //    forces at least one of the cache-key components to change.
    utimes(url.path, nil)
    utimes(iconURL.path, nil)

    // 2. Explicit "I changed something here, please re-look" hint to
    //    LaunchServices/Finder. Notify both the volume URL AND the icns
    //    file URL — Finder caches them in separate buckets, and the hidden
    //    leading-dot `.VolumeIcon.icns` path is its own cache entry distinct
    //    from the containing directory.
    let workspace = NSWorkspace.shared
    workspace.noteFileSystemChanged(url.path)
    workspace.noteFileSystemChanged(iconURL.path)
}

/// Apply the FinderInfo `kHasCustomIcon` flag with a forced state transition
/// (clear → set). On first apply this degrades to a plain set; on overwrite
/// it generates an off-then-on transition that's a stronger "icon changed"
/// signal than just re-writing the same byte.
///
/// In practice: not enough on its own to defeat Finder's icon-services
/// cache on overwrite (per Sigil v1.0.1 testing), but kept as correct
/// hygiene and in case a future macOS release tightens up the cache.
private static func cycleCustomIconFlag(on volumeURL: URL) throws {
    try clearCustomIconFlag(on: volumeURL)
    try setCustomIconFlag(on: volumeURL)
}
```

`clearCustomIconFlag` and `setCustomIconFlag` are read-modify-write of the
32-byte `com.apple.FinderInfo` xattr, touching only byte 8 (where
`kHasCustomIcon` lives at bit 0x04) and preserving any other bytes (Finder
colour labels etc.). When clearing leaves all 32 bytes zero, remove the
xattr entirely — that's the cleanest "FinderInfo doesn't exist" signal to
Finder for the brief window before re-setting.

## Why "discouraged" `noteFileSystemChanged` is still right here

Apple's docs say `NSWorkspace.noteFileSystemChanged(_:)` is discouraged in
favor of FSEvents. **That guidance is for *receiving* notifications.**
FSEvents is the right tool when you want to *listen* for changes.
`noteFileSystemChanged` is the right tool when you want to *push* a "hey,
re-look at this path" hint to LaunchServices/Finder. There's no FSEvents
replacement for the push case; the API is unchanged, unmarked-deprecated,
and used by every serious custom-icon CLI on the platform (`fileicon`,
`iconset`, etc.).

## What doesn't work, and why

### `LSRegisterURL`
Forces LaunchServices to re-register a URL. Documented for app bundles,
not file icons. Tested in Sigil dev — no observable effect on volume icon
refresh.

### Quick Look cache (`qlmanage -r`)
Affects only Quick Look's preview cache, not Finder's icon. Can mislead
diagnosis: Quick Look may show a stale icns preview while Finder shows a
correctly refreshed icon, or vice versa. Always sanity-check with
`shasum` of the actual file rather than trusting Quick Look.

### AppleScript `tell application "Finder" to update <volume>`
Works (Finder does refresh) but requires Automation permission. Heavy for
the use case; users get a permission prompt for a 50-byte refresh hint.
Avoid unless your app has Automation permission for other reasons.

### Eject + remount via DiskArbitration
The nuclear option that always works. Disruptive UX (volume disappears
for ~1-2 seconds) and adds significant code surface. Defensible only as
a user-triggered "Refresh" action, not silently in the apply path.

## Diagnostic: is it Finder cache or a real write failure?

When Finder shows a different icon than what you expect to be on disk,
verify which side is lying:

```sh
shasum /Volumes/<vol>/.VolumeIcon.icns \
       ~/Library/Application\ Support/<your-app>/icons/<key>.icns
```

If the hashes match, your write succeeded — it's Finder's cache. If they
differ, the write was dropped (real bug, possibly card filesystem corruption
or hardware-level issue).

This diagnostic saved Sigil's v1.0.1 from a false "Apply ignored zoom" bug
hunt; the bytes were correct on disk, the cache was the culprit.

## When to give up

If your feature requires Finder to reliably reflect *every* icon overwrite,
and the eject-remount UX cost is unacceptable, **remove the feature**.
That's what Sigil did with the zoom slider in v1.0.1: the in-app preview
was correct, the on-disk icns was correct, but Finder serving stale
thumbnails made the slider visibly broken to users. Better to ship a
narrower tool that always looks right than a richer tool that sometimes
doesn't.

## Sources

- [Apple Developer Documentation — `NSWorkspace.noteFileSystemChanged`](https://developer.apple.com/documentation/appkit/nsworkspace/1579268-notefilesystemchanged)
- [`fileicon` CLI (mklement0)](https://github.com/mklement0/fileicon) — reference implementation
- [`iconset` CLI (tale)](https://github.com/tale/iconset) — also dual-notification

## Related

- `cookbook/30-color-managed-icon-pipeline.md` — the *previous* step in the
  icon-rendering chain (write the right bytes, in the right color space).
- `cookbook/32-removable-volumes-tcc.md` — the *first* step (have permission
  to write to the volume root in the first place on macOS 13+).
