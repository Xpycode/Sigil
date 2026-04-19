# Shipping Sigil

Two paths:

1. **Canonical — Xcode GUI + Managed Developer ID** (what we actually use).
   Uses the Xcode Cloud-managed "Developer ID Application Managed" cert that
   lives on Apple's servers. You don't have the private key locally; Xcode
   handles all signing/notarization/stapling via Apple's services. Simpler,
   less moving parts, works from any Mac you're signed into with your Apple ID.

2. **Appendix — Pure CLI pipeline** (for CI or future automation).
   Requires a locally-installed Developer ID Application certificate. Not
   currently used for Sigil — kept here for reference if we ever move the
   release to GitHub Actions.

---

## Canonical path — per release

### 1. Pre-flight

- `main` is green (31 tests passing).
- Version bumped in `01_Project/project.yml`:
  ```yaml
  CFBundleShortVersionString: "1.0.0"   # user-facing
  CFBundleVersion: "1"                  # build number — increment for every Apple submission
  MARKETING_VERSION: "1.0.0"
  CURRENT_PROJECT_VERSION: "1"
  ```
- Regenerate: `cd 01_Project && xcodegen generate`.
- Commit the bump on a release branch.

### 2. Archive + notarize via Xcode

1. Open `01_Project/Sigil.xcodeproj`.
2. In the scheme toolbar, destination → **Any Mac (Apple Silicon, Intel)**, configuration → **Release**.
3. **Product → Archive** (menu bar, or `⌘B` after setting scheme → Release).
   Xcode builds, archives, and opens the **Organizer**.
4. In the Organizer, select the new archive → **Distribute App**.
5. Choose **Direct Distribution**. Xcode will:
   - Sign with the managed Developer ID Application certificate
   - Upload the `.app` to Apple for notarization
   - Wait for notarization (usually 1-3 minutes)
   - Staple the notarization ticket to the `.app`
   - Offer to **Export** the signed + stapled `.app`
6. Export to `04_Exports/` as a folder like `Sigil-1.0.0-export/`.

Verification:
```bash
xcrun stapler validate 04_Exports/Sigil-1.0.0-export/Sigil.app
# Expected: "The validate action worked!"

spctl --assess --type execute -vv 04_Exports/Sigil-1.0.0-export/Sigil.app
# Expected: "accepted" with "source=Notarized Developer ID"
```

### 3. Wrap in a DMG

Using `create-dmg` (install with `brew install create-dmg`):

```bash
create-dmg \
    --volname "Sigil 1.0.0" \
    --window-size 560 360 \
    --icon-size 100 \
    --icon "Sigil.app" 160 180 \
    --app-drop-link 400 180 \
    --hide-extension "Sigil.app" \
    --no-internet-enable \
    04_Exports/Sigil-1.0.0.dmg \
    04_Exports/Sigil-1.0.0-export/
```

Hand-roll fallback (no extra dependency):

```bash
hdiutil create -volname "Sigil 1.0.0" \
               -srcfolder 04_Exports/Sigil-1.0.0-export \
               -ov -format UDZO \
               04_Exports/Sigil-1.0.0.dmg
```

Then verify the DMG is also valid under Gatekeeper:

```bash
spctl --assess --type open --context context:primary-signature -v 04_Exports/Sigil-1.0.0.dmg
# Expected: "accepted" (the stapled ticket on the inner .app covers the DMG)
```

### 4. Test on a clean user or second Mac

Copy the DMG to a different user account (or a second Mac). Double-click. If you see **no Gatekeeper warning** and the app opens cleanly, you're good.

### 5. Tag + push

```bash
git tag -a v1.0.0 -m "Sigil 1.0.0"
git push origin main v1.0.0
```

### 6. GitHub Release

```bash
gh release create v1.0.0 \
    --repo Xpycode/Sigil \
    --title "Sigil 1.0.0" \
    --notes-file 04_Exports/RELEASE-NOTES-1.0.0.md \
    04_Exports/Sigil-1.0.0.dmg
```

### 7. Verify the release

```bash
gh release view v1.0.0 --repo Xpycode/Sigil
```

Confirm the DMG is attached and the notes render. Copy the release URL and paste it into the README's Install section.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Xcode "No profiles matching this ID" | Managed cert hasn't propagated yet | Wait 5 min, restart Xcode, retry Archive |
| Archive builds but Distribute App button greyed out | Wrong configuration (Debug, not Release) or missing signing | Scheme → Edit Scheme → Archive → Release |
| `stapler validate` fails after export | `.app` was modified post-staple | Re-export from Organizer |
| DMG has the `.app` but Gatekeeper warns | `.app` wasn't stapled before DMG packaging | Run `xcrun stapler staple` on the `.app`, rebuild DMG |
| `spctl` returns "rejected" | Notarization didn't complete or isn't stapled | Check Xcode Organizer → Archive → Notarization status |
| Gatekeeper warning on second Mac but not yours | Your Mac's trust DB cached the signature | Try on a user account you've never used with Sigil |

---

## Appendix — Pure CLI pipeline (NOT used for Sigil releases)

Reference only. Requires a **locally-installed** Developer ID Application certificate — not the managed one. To obtain one:

1. [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list) → **+**
2. Select "Developer ID Application" (NOT "Developer ID Application Managed")
3. Upload a CSR generated via Keychain Access → Certificate Assistant
4. Download and install the resulting `.cer`

Verify: `security find-identity -p codesigning -v | grep "Developer ID Application"`

Then run (one-time):

```bash
xcrun notarytool store-credentials "sigil-notary" \
    --apple-id "your.appleid@example.com" \
    --team-id "FDMSRXXN73" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

(The password is an app-specific password from appleid.apple.com.)

Per-release:

```bash
# Archive (Release)
xcodebuild -scheme Sigil -configuration Release \
           -destination 'generic/platform=macOS' \
           -archivePath 04_Exports/Sigil-1.0.0.xcarchive \
           archive

# Export signed .app (need ExportOptions.plist with method: "developer-id")
xcodebuild -exportArchive \
           -archivePath 04_Exports/Sigil-1.0.0.xcarchive \
           -exportOptionsPlist 04_Exports/ExportOptions.plist \
           -exportPath 04_Exports/Sigil-1.0.0-export

# Notarize
(cd 04_Exports/Sigil-1.0.0-export && zip -r Sigil.zip Sigil.app)
xcrun notarytool submit 04_Exports/Sigil-1.0.0-export/Sigil.zip \
      --keychain-profile "sigil-notary" --wait

# Staple + build DMG (same as canonical path from here)
xcrun stapler staple 04_Exports/Sigil-1.0.0-export/Sigil.app
# ... then create-dmg ...
```

This path is useful only if you ever move releases to GitHub Actions or similar. For a solo dev, the GUI path is strictly better.
