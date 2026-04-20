# Sigil — Custom Volume Icons

A small macOS app that assigns custom icons to external volumes and remembers icons for unmounted volumes (re-applying when the volume returns).

> **Working codename was "CVI"** (Custom Volume Icons). The product ships as **Sigil** and the working directory is `1-macOS/Sigil/`. Historical references to "CVI" remain in `docs/decisions.md` and older session logs as part of the project record.

---

## Identity

| Field | Value |
|-------|-------|
| Product name | **Sigil** |
| Bundle ID | `com.lucesumbrarum.sigil` |
| Organization | Luces Umbrarum |
| Distribution | GitHub Releases (notarized DMG), non-sandboxed |
| Min macOS | 14.0 (Sonoma) |
| App Support dir | `~/Library/Application Support/Sigil/` |
| Logger subsystem | `com.lucesumbrarum.sigil` |

---

## Status

**Phase:** Plan complete → ready for **Build (Wave 0)**.
See `docs/PROJECT_STATE.md` for funnel position and `IMPLEMENTATION_PLAN.md` for the wave plan.

---

## How to work in this repo

1. **Read `docs/00_base.md`** at the start of every session — it defines the Directions workflow.
2. **Check `docs/PROJECT_STATE.md`** for current phase, focus, and blockers.
3. **Read `IMPLEMENTATION_PLAN.md`** before starting any wave.
4. **Read the relevant cookbook entries** (`docs/cookbook/00-app-shell.md` is mandatory for the chrome).
5. **Log decisions** in `docs/decisions.md` as soon as they're made.
6. **Log sessions** in `docs/sessions/YYYY-MM-DD.md` after significant progress.

## Folder layout

```
Sigil/                            ← working directory
├── 01_Project/                   ← Xcode project + source (Sigil.xcodeproj, Sigil/)
├── 02_Design/                    ← Affinity icon source, mockups
│   └── Exports/                  ← AppIcon.appiconset
├── 03_Screenshots/               ← Promotional screenshots
├── 04_Exports/                   ← DMGs, signed builds (gitignored)
├── docs/                         ← Directions documentation
│   ├── 00_base.md
│   ├── PROJECT_STATE.md
│   ├── decisions.md
│   └── sessions/
├── specs/
│   └── sigil-v1.md               ← Source-of-truth feature spec
├── IMPLEMENTATION_PLAN.md        ← Wave-based task plan
├── CLAUDE.md                     ← This file
└── .gitignore
```

## Domain primer

- **Volume icon storage:** macOS reads a hidden `.VolumeIcon.icns` at the root of a volume, **plus** the `kHasCustomIcon` flag in `com.apple.FinderInfo`, to display a custom icon.
- **Why this app exists:** the icon lives on the volume itself, so it's lost when the volume is reformatted, used on another machine, or simply unmounted. Sigil keeps a local database of (volume UUID → icon) mappings so the icon can be re-applied on remount.
- **Critical implementation note:** `NSWorkspace.setIcon` is broken on volume roots since macOS 13.1 (writes the file but fails to set the FinderInfo flag). Sigil writes both pieces directly via `Data.write` + `setxattr`. See `docs/decisions.md` 2026-04-19 for the full reasoning.

## Architectural rules (locked in, per spec)

- ViewModels: `@MainActor @Observable`
- Services: `actor`
- Models: `struct` (Codable, Sendable)
- Persistence: JSON in `~/Library/Application Support/Sigil/` with atomic write + `.bak` fallback
- Logger: `os.Logger` with subsystem `com.lucesumbrarum.sigil` and categories `mount` / `io` / `render` / `ui`
- No `try?` swallowing errors
- No force-unwrap without nil guard
- App Shell Standard mandatory (`docs/cookbook/00-app-shell.md`)

## Build commands (placeholder — fill in once Xcode project exists in Wave 0)

```bash
# Clean
xcodebuild clean -scheme Sigil -destination 'platform=macOS'

# Build
xcodebuild -scheme Sigil -destination 'platform=macOS' build

# Test
xcodebuild test -scheme Sigil -destination 'platform=macOS'

# Launch built app
open 01_Project/build/Debug/Sigil.app
```
