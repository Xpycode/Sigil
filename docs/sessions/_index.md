# Session History — CVI

## Active Project
CVI (Custom Volume Icons) — macOS utility for managing custom icons on external volumes, including remembering icons for unmounted volumes.

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-04-19 | Sigil: inception → ship-ready in one session | **Waves 0–9 all shipped.** 31 tests green. Real-hardware smoke tests for the xattr-based two-step icon write AND smart-silent re-apply on remount both confirmed working by user. Repo pushed to `github.com/Xpycode/Sigil`. Only the Xcode Archive + Direct-Distribution notarize remains (user-driven). | [log](2026-04-19.md) |
| 2026-04-20 | Detail-view redesign + zoom slider + re-zoom from cache + Fit/Fill UI removal | Fixed clipped-Apply layout bug; new default window 1000×720; compact metadata; action row merged into editor; zoom slider (0.5×–3.0×) with fast-preview path; sliders now work on already-applied icons without re-import; caught and fixed `IconCache.saveSource` src==dest destructive-delete bug. Follow-up: dropped Fit/Fill picker (invisible on square icons) — zoom is the single framing axis now. Merged and pushed to main. | [log](2026-04-20.md) |
| 2026-04-20 (evening) | Pre-publish polish + v1.0.0 ship | Click-to-browse canvas (Browse button dropped), inline `×` overlay for clear, preview image clipped to rounded corners, zoom+buttons reorganised into the right column centered against the canvas. README rewritten in CropBatch house style with inline app-icon H1, 6 badges, 4 real screenshots. Notarized DMG built via `hdiutil` from `ditto`-copied `.app`, verified stapled + Gatekeeper-accepted. Tag `v1.0.0` pushed and GitHub release published with DMG asset. **Project shipped.** | [log](2026-04-20-b.md) |

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
