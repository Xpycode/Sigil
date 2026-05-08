# Project State — Sigil

> Size limit: <100 lines. This is a digest, not an archive.

## Identity
- **Product:** Sigil  *(working codename: CVI)*
- **Bundle ID:** `com.lucesumbrarum.sigil`
- **Working directory:** `1-macOS/Sigil/`
- **One-liner:** A small macOS app that assigns custom icons to external volumes and remembers icons for unmounted volumes (re-applying when the volume returns).
- **Tags:** macOS, SwiftUI, Finder, volumes, utility, niche
- **Started:** 2026-04-19

## Current Position
- **Funnel:** **done** — **v1.0.1 shipped** (https://github.com/Xpycode/Sigil/releases/tag/v1.0.1)
- **Phase:** shipped
- **Focus:** v1.0.1 released as a maintenance update fixing two v1.0.0 bugs surfaced by real-hardware testing: (1) APFS-only disk-space probe falsely reported "Zero KB" on every non-APFS volume; (2) missing `NSRemovableVolumesUsageDescription` made macOS silently deny removable-volume writes since macOS 13. Plus polish: Forget-button removal from mounted view, header icon shows actual icon, Reset/Forget fully reset editor, sRGB color pipeline, dual-path Finder cache invalidation, FinderInfo flag toggle. **Zoom slider removed** — Finder's icon-services cache reliably refused to refresh on overwrite, making the slider visibly broken even though the icns on disk was correct. Editor is now Drop → Apply.
- **Status:** v1.0.1 shipped (notarized DMG, 12.0 MB, attached to GitHub release)
- **Last updated:** 2026-05-08
- **Test count:** 31 green (zoom + IconCache regression tests still pending — slated for v1.1; less urgent now that zoom is gone)
- **Repo:** `github.com/Xpycode/Sigil` — `main` at `8b43f82`. Tags `v1.0.0` + `v1.0.1` pushed; v1.0.1 DMG (12 MB, notarized + stapled) attached to the latest release. 9 wave tags + 4 feature branches in history (`feature/ui-redesign-zoom`, `feature/drop-fit-fill-ui`, `feature/release-polish-v1.0.0`, `fix/v1.0.1`).
- **App icon:** Wax-seal, blackletter S on obsidian (Kling-generated from Prompt A). `AppIcon.appiconset` wired at 10 sizes.
- **Signing:** Managed Developer ID Application (team `FDMSRXXN73`, Luces Umbrarum). No local Developer ID cert needed — Xcode handles via Apple's services.

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Spec written with acceptance criteria (`specs/sigil-v1.md`) |
| **Plan** | done | `IMPLEMENTATION_PLAN.md`, 10 waves, backpressure defined |
| **Build** | done | Waves 0-9 shipped; post-ship UX polish merged 2026-04-20 |
| **Ship** | done | Tagged `v1.0.0` + `v1.0.1`; latest notarized DMG (v1.0.1) attached to GitHub Release |

## Phase Progress

```
[####################] 100% — v1.0.1 live at github.com/Xpycode/Sigil/releases/tag/v1.0.1
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | 4-phase interview complete; spec at `specs/sigil-v1.md` |
| Planning | done | `IMPLEMENTATION_PLAN.md` — 10 waves, ~17 build-hours |
| Implementation | done | Waves 0-9 on main; post-ship redesign + zoom on main |
| Polish | done | App icon, README rewrite (CropBatch style), signing config, UX polish 2026-04-20 |
| Shipping | done | Archive → Direct Distribution → DMG (12 MB, UDZO) → tag `v1.0.0` → `gh release create`. Maintenance v1.0.1 shipped 2026-05-04 via `fix/v1.0.1` → `--no-ff` merge. |

## Readiness

| Dimension | Status | Notes |
|-----------|--------|-------|
| Features | ✅ done | Full spec + post-release zoom/re-zoom additions |
| UI/Polish | ✅ done | App Shell Standard; detail-view redesign + click-to-browse + inline clear + rounded preview shipped 2026-04-20 |
| Testing | 🟡 partial | 31 green; zoom pipeline + IconCache regression tests deferred to v1.0.1 |
| Docs | ✅ done | Directions, spec, decisions, session logs current; README in CropBatch house style |
| Distribution | ✅ done | v1.0.1 live on GitHub Releases (notarized + stapled DMG, 12 MB) |

## Validation Gates
- [x] **Define → Plan**: Spec with acceptance criteria
- [x] **Plan → Build**: Atomic tasks identified, backpressure chain defined
- [x] **Build → Ship**: Signed + notarized + stapled DMG released as `v1.0.0` then patched to `v1.0.1` (regression tests for zoom/IconCache deferred — not a ship blocker; zoom slider since removed in v1.0.1)

## Active Decisions
<!-- Last 3-5 decisions only. Full history in decisions.md -->
- 2026-05-04: **Removable-volume TCC** — declared `NSRemovableVolumesUsageDescription` in Info.plist with user-validated copy ("To apply the icon you chose, Sigil writes a small icon file to the drive's root so it appears in Finder."). Without this key, macOS 13+ silently denied writes to removable-volume roots, with no in-app or System Settings path to grant access. Bumped to v1.0.1 / build 2; improved `permissionDenied` error to point at the System Settings pane.
- 2026-05-04: **Disk-space preflight: dual-key probe, skip-on-unknown** — `volumeAvailableCapacityForImportantUsageKey` is APFS-only and returns `0` on ExFAT/FAT32/HFS+. Added `volumeAvailableCapacityKey` fallback with `> 0` guard; on truly unknown capacity, skip the preflight and let the kernel report ENOSPC at write time. Cookbook 29 had the same flaw — fixed at source.
- 2026-04-20 (evening): **Click-to-browse consolidation** — whole canvas is the file-picker affordance; inline `xmark.circle.fill` overlay replaces the Clear button; preview image clipped to inner-radius 8 to visually parallel outer radius 10. Zoom slider lives in the right column, vertically centered against the canvas with the action buttons.
- 2026-04-20 (evening): **README follows CropBatch template** — inline H1 icon, 6 badges, screenshots-above-features, keyboard-shortcut table. Establishes Luces Umbrarum house style across app releases.
- 2026-04-20: **Zoom is the single framing axis.** Fit/Fill picker removed from UI (invisible on square icons). Zoom 1.0 = Fit-equivalent; zoom = aspect_ratio = Fill-equivalent. `VolumeRecord.fitMode` kept for legacy back-compat. Pan deferred as future second axis.

## Open questions
- App icon design starting point (Wave 9 only — not blocking Build).
- Apple Developer account in hand for notarization (Wave 9 only).
- Xcode project creation path: open Xcode UI manually, or install `xcodegen` so I can scaffold from a `project.yml`?

## Blockers
<!-- Empty = good. -->

## Resume
<!-- If RESUME.md exists, note it here. -->

---
*Source of truth for project position. Updated after every meaningful step.*
