# Project State — CVI

> Size limit: <100 lines. This is a digest, not an archive.

## Identity
- **Product:** Sigil  *(working codename: CVI)*
- **Bundle ID:** `com.lucesumbrarum.sigil`
- **Working directory:** `1-macOS/CVI/` (codename retained for path stability)
- **One-liner:** A small macOS app that assigns custom icons to external volumes and remembers icons for unmounted volumes (re-applying when the volume returns).
- **Tags:** macOS, SwiftUI, Finder, volumes, utility, niche
- **Started:** 2026-04-19

## Current Position
- **Funnel:** **ship** — code shipped to main; awaiting notarized .app + DMG + GitHub Release
- **Phase:** shipping + post-ship UX polish
- **Focus:** User runs Xcode Archive → Direct Distribution. Claude then builds DMG + pushes GitHub release. Today's UX polish (detail-view redesign + zoom) folds into the same release.
- **Status:** ready
- **Last updated:** 2026-04-20
- **Test count:** 31 green (zoom feature + IconCache fix not yet covered — next session)
- **Repo:** `github.com/Xpycode/Sigil` — `main` at `1cc2331`. 9 wave tags + 2 feature branches pushed (`feature/ui-redesign-zoom`, `feature/drop-fit-fill-ui`).
- **App icon:** Wax-seal, blackletter S on obsidian (Kling-generated from Prompt A). `AppIcon.appiconset` wired at 10 sizes.
- **Signing:** Managed Developer ID Application (team `FDMSRXXN73`, Luces Umbrarum). No local Developer ID cert needed — Xcode handles via Apple's services.

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Spec written with acceptance criteria (`specs/sigil-v1.md`) |
| **Plan** | done | `IMPLEMENTATION_PLAN.md`, 10 waves, backpressure defined |
| **Build** | done | Waves 0-9 shipped; post-ship UX polish merged 2026-04-20 |
| **Ship** | in progress | Archive + notarize + DMG + GitHub Release pending |

## Phase Progress

```
[####################] 99% — code complete on main; final step is the notarized-DMG release
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | 4-phase interview complete; spec at `specs/sigil-v1.md` |
| Planning | done | `IMPLEMENTATION_PLAN.md` — 10 waves, ~17 build-hours |
| Implementation | done | Waves 0-9 on main; post-ship redesign + zoom on main |
| Polish | done | App icon, README, signing config (Wave 9); UX polish 2026-04-20 |
| Shipping | in progress | Archive → Direct Distribution → DMG → GitHub Release |

## Readiness

| Dimension | Status | Notes |
|-----------|--------|-------|
| Features | ✅ done | Full spec + post-release zoom/re-zoom additions |
| UI/Polish | ✅ done | App Shell Standard; detail-view redesign shipped 2026-04-20 |
| Testing | 🟡 partial | 31 green; zoom pipeline + IconCache fix need coverage |
| Docs | ✅ done | Directions, spec, decisions, session logs current |
| Distribution | 📋 pending | GitHub Releases (notarized DMG) — user-driven next step |

## Validation Gates
- [x] **Define → Plan**: Spec with acceptance criteria
- [x] **Plan → Build**: Atomic tasks identified, backpressure chain defined
- [ ] **Build → Ship**: All tests green, signed + notarized build

## Active Decisions
<!-- Last 3-5 decisions only. Full history in decisions.md -->
- 2026-04-20: **Zoom is the single framing axis.** Fit/Fill picker removed from UI (invisible on square icons). Zoom 1.0 = Fit-equivalent; zoom = aspect_ratio = Fill-equivalent. `VolumeRecord.fitMode` kept for legacy back-compat. Pan deferred as future second axis.
- 2026-04-20: **Fast preview path** — `IconRenderer.preview` stops at `ImageNormalizer.normalize` (skips `iconutil` subprocess) so zoom slider feels live.
- 2026-04-20: `IconCache.saveSource` guards against `src == dest` (destructive self-delete bug caught during re-zoom-from-cache flow).
- 2026-04-19: **Product name = Sigil**; bundle ID `com.lucesumbrarum.sigil`; org "Luces Umbrarum". Working dir stays `1-macOS/CVI/`.
- 2026-04-19: Icon-application = **direct two-step write** (not `NSWorkspace.setIcon` — broken on volumes since macOS 13.1). Write `.VolumeIcon.icns` + set `com.apple.FinderInfo` xattr byte 8 = 0x04 + `utimes` to refresh.

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
