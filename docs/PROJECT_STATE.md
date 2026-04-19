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
- **Funnel:** build (Waves 0–4 done; Wave 5 next — the critical risk wave)
- **Phase:** implementation
- **Focus:** Wave 5 — IconApplier (xattr + atomic write to `/Volumes/X/.VolumeIcon.icns`), the central spec risk
- **Status:** ready
- **Last updated:** 2026-04-19
- **Test count:** 17 green

## Funnel Progress

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Spec written with acceptance criteria (`specs/sigil-v1.md`) |
| **Plan** | done | `IMPLEMENTATION_PLAN.md`, 10 waves, backpressure defined |
| **Build** | next | Tests pass, review done; starts at Wave 0 |

## Phase Progress

```
[###############.....] 73% — Waves 0-4 shipped (+ icon rendering pipeline); Wave 5 is the xattr risk wave
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | 4-phase interview complete; spec at `specs/sigil-v1.md` |
| Planning | done | `IMPLEMENTATION_PLAN.md` — 10 waves, ~17 build-hours |
| Implementation | next | Start at Wave 0 once bundle ID is decided |
| Polish | pending | Wave 9 |
| Shipping | pending | Notarization + DMG packaging (Wave 9) |

## Readiness

| Dimension | Status | Notes |
|-----------|--------|-------|
| Features | ✅ specified | See `specs/sigil-v1.md` acceptance criteria |
| UI/Polish | ⚪ — | App Shell Standard locked in; build pending |
| Testing | ⚪ — | XCTest for services; manual flow for UI |
| Docs | ✅ done | Directions installed, spec written, decisions logged |
| Distribution | 📋 planned | GitHub Releases (notarized DMG) |

## Validation Gates
- [ ] **Define → Plan**: Spec with acceptance criteria
- [ ] **Plan → Build**: Atomic tasks identified, backpressure chain defined
- [ ] **Build → Ship**: All tests green, signed + notarized build

## Active Decisions
<!-- Last 3-5 decisions only. Full history in decisions.md -->
- 2026-04-19: **Product name = Sigil**; bundle ID `com.lucesumbrarum.sigil`; org "Luces Umbrarum". Working dir stays `1-macOS/CVI/`.
- 2026-04-19: Icon-application = **direct two-step write** (not `NSWorkspace.setIcon` — broken on volumes since macOS 13.1). Write `.VolumeIcon.icns` + set `com.apple.FinderInfo` xattr byte 8 = 0x04 + `utimes` to refresh.
- 2026-04-19: UI shell = Tier 1 (plain window app); HSplitView + App Shell Standard
- 2026-04-19: Persistence = JSON in `~/Library/Application Support/Sigil/`; UUID-only identity; smart-silent auto-reapply with hash-conflict fallback
- 2026-04-19: Distribution = GitHub direct download (notarized DMG), non-sandboxed; min macOS = 14.0; weekend scope

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
