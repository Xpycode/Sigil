# Session History — Sigil

## Active Project
Sigil *(working codename: CVI)* — macOS utility for managing custom icons on external volumes, including remembering icons for unmounted volumes.

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-04-19 | Sigil: inception → ship-ready in one session | **Waves 0–9 all shipped.** 31 tests green. Real-hardware smoke tests for the xattr-based two-step icon write AND smart-silent re-apply on remount both confirmed working by user. Repo pushed to `github.com/Xpycode/Sigil`. Only the Xcode Archive + Direct-Distribution notarize remains (user-driven). | [log](2026-04-19.md) |
| 2026-04-20 | Detail-view redesign + zoom slider + re-zoom from cache + Fit/Fill UI removal | Fixed clipped-Apply layout bug; new default window 1000×720; compact metadata; action row merged into editor; zoom slider (0.5×–3.0×) with fast-preview path; sliders now work on already-applied icons without re-import; caught and fixed `IconCache.saveSource` src==dest destructive-delete bug. Follow-up: dropped Fit/Fill picker (invisible on square icons) — zoom is the single framing axis now. Merged and pushed to main. | [log](2026-04-20.md) |
| 2026-04-20 (evening) | Pre-publish polish + v1.0.0 ship | Click-to-browse canvas (Browse button dropped), inline `×` overlay for clear, preview image clipped to rounded corners, zoom+buttons reorganised into the right column centered against the canvas. README rewritten in CropBatch house style with inline app-icon H1, 6 badges, 4 real screenshots. Notarized DMG built via `hdiutil` from `ditto`-copied `.app`, verified stapled + Gatekeeper-accepted. Tag `v1.0.0` pushed and GitHub release published with DMG asset. **Project shipped.** | [log](2026-04-20-b.md) |
| 2026-04-20 (night) | CVI → Sigil folder rename cleanup | User renamed working directory from `1-macOS/CVI/` to `1-macOS/Sigil/`. Audit confirmed no functional breakage (Xcode project uses relative paths; DerivedData re-keyed cleanly; git remote already `Xpycode/Sigil.git`). Synced 4 forward-looking docs (`CLAUDE.md`, `IMPLEMENTATION_PLAN.md`, `specs/sigil-v1.md`, `docs/PROJECT_STATE.md`) to the new path; left `decisions.md` and session logs as append-only historical record. Set upstream tracking on `main` (`git push -u origin main`). Committed `68805b3` + pushed. | [log](2026-04-20-c.md) |
| 2026-05-04 | **v1.0.1 shipped** — ExFAT disk-space + Removable Volumes TCC + 7 follow-up fixes | Day-long iterative session driven by real-hardware testing on a 512 GB ExFAT CFExpress B card. Started from "Volume is full — Zero KB" report; fixed APFS-only disk-space probe and added `NSRemovableVolumesUsageDescription` for macOS 13+ TCC. Then 7 more rounds: detail-header icon, Forget editor reset, sRGB color pipeline, removed redundant Forget button from mounted view, Finder cache invalidation (3 escalating attempts), dropped zoom slider entirely (Finder cache won), FinderInfo flag toggle. One non-Sigil incident: ExFAT bitmap corruption mid-session (CFexpress controller dropped a metadata flush; fsck repaired). Notarized DMG (12.0 MB) shipped at https://github.com/Xpycode/Sigil/releases/tag/v1.0.1. Six new decision entries in `docs/decisions.md`. Branch `fix/v1.0.1` merged via `--no-ff` to `main`. | [log](2026-05-04.md) |
| 2026-04-20 (late night) | Retrospective code review of v1.0.0 | User flagged that `/code-review` had been skipped before shipping. Reviewed `feature/release-polish-v1.0.0` branch (2 Swift files + README). Security: clean. Found 3 quality issues for a v1.0.1 polish pass: (1) `NSCursor.push/pop` unbalanced under view-disappear in `IconDropZone.swift`, (2) float-equality on `pendingZoom == 1.0` in `VolumeDetailView.swift`, (3) 160pt sidebar column cramps the relocated zoom slider. No blockers; v1.0.0 shipped without material defects. Review-only, no commits. | [log](2026-04-20-d.md) |
| 2026-05-08 | README + screenshots aligned with shipped v1.0.1 | Verified v1.0.1 release/DMG are correctly published on GitHub. Caught README still on v1.0.0: badges, install-step DMG filename (`Sigil-v1.0.0.dmg` → `Sigil-1.0.1.dmg` — also fixed the misleading `v` prefix), plus stale references to the removed zoom slider in Features / Usage / Data sections and two screenshot captions. Refreshed screenshots: re-shot Hero + Applied on v1.0.1 chrome, added new `Sigil-2-Permission.png` showing the macOS Removable Volumes TCC dialog (introduced by v1.0.1's `NSRemovableVolumesUsageDescription`). Caught a near-miss: `Sigil-3-applied.png` first-pass was just the Apr 20 file renumbered, still showing the v1.0.0 zoom slider — flagged via file timestamp before commit. Two commits pushed: `2655643` (text/version) and `8b43f82` (screenshots). Deliberately kept `var zoom: Double` in `VolumeRecord` for v1.0.0 save-decode compatibility. No code changes. | [log](2026-05-08.md) |

---

## Session Log Template

When starting a new session, create a file: `sessions/YYYY-MM-DD.md` (add `-a`, `-b`, etc. for multiple sessions per day).

```markdown
# Session: YYYY-MM-DD

## Goal
[What we're trying to accomplish]

## Context
- Previous session: [link or summary]
- Current phase: [discovery|planning|implementation|polish|shipping]

## Progress

### Completed
- [x] [What got done]

### In Progress
- [ ] [What's being worked on]

### Discovered
- [New things learned]

### Decisions Made
- [Decision] → logged in decisions.md

### Blockers
- [Anything blocking progress]

## Next Session
- [What to do next]

## Notes
[Anything else worth remembering]
```

---
*One log per session. Link from here.*
