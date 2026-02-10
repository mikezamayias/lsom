# lsom Beta Release Process

## Overview

Beta releases are automatically built, signed, notarized, and published to GitHub Releases via GitHub Actions.

## Current Release Status

- **Latest Release:** v0.1.3
- **Beta Version:** v0.2.0-beta.1 (ready to release)
- **Workflow:** GitHub Actions (configured in `.github/workflows/release.yml`)

## Beta Release Checklist

### Pre-Release

- [x] Battery display implementation (real-time via IOKit/HID++)
- [x] DPI control (read/write with UI)
- [x] Polling rate control (read/write with UI)
- [x] Settings UI with toggle options
- [x] Auto-refresh timer (5s, 1m, 5m, 15m intervals)
- [x] Permission handling (Input Monitoring)
- [x] Device connection detection
- [x] Settings persistence via UserDefaults
- [x] Code builds successfully (Release configuration)
- [x] GitHub Actions workflow tested

### Known Limitations for Beta

- Single device support (only shows one paired mouse)
- Unifying Receiver only (PID 0xC547)
- No profile management
- No cloud sync (planned for Phase 3)
- No auto-update mechanism yet (Sparkle integration pending)

## How to Release

### Option 1: Git Tag (Recommended)

```bash
cd ~/Developer/Swift/lsom

# Create and push the beta tag
git tag -a v0.2.0-beta.1 -m "Beta release: Battery, DPI, Polling Rate controls"
git push origin v0.2.0-beta.1
```

**Result:** GitHub Actions automatically:
1. Builds the app (Release configuration)
2. Signs with Developer ID certificate (if available)
3. Notarizes via Apple notarization service
4. Creates GitHub Release with release notes
5. Uploads `lsom.zip` and checksums

### Option 2: Workflow Dispatch

Push to GitHub and trigger via Web UI:
1. Go to **Actions** tab on GitHub
2. Select **Release** workflow
3. Click **Run workflow**
4. Enter version: `0.2.0-beta.1`
5. Confirm

## Release Artifacts

When the workflow completes, the GitHub Release will include:

- `lsom.zip` - Signed and notarized app bundle
- `checksums-sha256.txt` - SHA-256 checksum for verification
- Release notes - Changelog since previous release

## For Beta Testers

1. **Download:** Go to GitHub Releases → v0.2.0-beta.1
2. **Extract:** Unzip `lsom.zip`
3. **Run:** Double-click `lsom.app` or drag to Applications
4. **Grant Permissions:** System Settings → Privacy & Security → Input Monitoring → Enable lsom
5. **Test:** Click menu bar icon to open popover

### Reporting Issues

- Create a GitHub Issue with:
  - macOS version
  - Logitech mouse model
  - Steps to reproduce
  - Screenshot if applicable
  - System log output (~/Library/Logs/lsom.log if available)

## Signing & Notarization Notes

### Developer ID Certificate

The workflow expects these GitHub Secrets:
- `DEVELOPER_ID_CERTIFICATE_BASE64` - Developer ID Application certificate (Base64)
- `DEVELOPER_ID_CERTIFICATE_PASSWORD` - Certificate password
- `TEAM_ID` - Apple Team ID
- `APPLE_ID` - Apple ID for notarization
- `APPLE_ID_PASSWORD` - App-specific password for notarization

If not configured, the workflow builds and releases unsigned (development mode).

### Notarization

Notarization is only run if `APPLE_ID` secret is set. Without notarization, macOS will show "unidentified developer" warning on first run.

To notarize manually:
```bash
# Create zip for notarization
ditto -c -k --keepParent build/export/lsom.app notarize.zip

# Submit for notarization (requires ~5-10 minutes)
xcrun notarytool submit notarize.zip \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# Staple the app
xcrun stapler staple build/export/lsom.app
```

## Next Steps After Beta

1. **Collect Feedback:** Review GitHub Issues from beta testers
2. **Fix Bugs:** Address critical issues found during beta
3. **Final Release:** Tag as v0.2.0 (non-beta) when ready
4. **ProductHunt:** Launch on ProductHunt (April timeline)

## Files

- **Release Workflow:** `.github/workflows/release.yml`
- **Build Workflow:** `.github/workflows/build.yml`
- **App Entry Point:** `lsom/Application/lsomApp.swift`
- **Version Source:** Info.plist (if you add CFBundleShortVersionString)

## Troubleshooting

### Build Fails with Code Signing Errors

Set code signing bypass for development:
```bash
xcodebuild build \
  -project lsom.xcodeproj \
  -scheme lsom \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO
```

### Notarization Takes Too Long

Notarization can take 5-15 minutes. Check status:
```bash
xcrun notarytool info [submission-id] \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --team-id "$TEAM_ID"
```

### App Says "Not Notarized"

Ensure the notarized app was stapled:
```bash
xcrun stapler validate lsom.app
```

---

**Last Updated:** 2026-02-10  
**Prepared for:** v0.2.0-beta.1 release
