# CI/CD Pipeline Setup

This document outlines the GitHub Actions CI/CD pipeline for **lsom**, configured per industry standards.

## Overview

- **Platform:** GitHub Actions
- **Runner:** Self-hosted (`mikes-macbook` - Apple Silicon, macOS)
- **Workflows:**
  - **build.yml** — Debug builds on push/PR to `main` & `dev`
  - **lint.yml** — SwiftLint checks on push/PR
  - **release.yml** — Archive, notarize, and create GitHub releases on tags or manual trigger

---

## Workflows

### 1. Build (build.yml)

**Trigger:** Push/PR to `main` or `dev`

**Steps:**
1. Checkout code
2. Select latest Xcode from `/Applications`
3. Build Debug configuration without code signing
4. Report result

**No secrets required.**

---

### 2. Lint (lint.yml)

**Trigger:** Push/PR to `main` or `dev`

**Steps:**
1. Checkout code
2. Run SwiftLint (if installed on runner)
3. Comment on PR with violations (if any)

**No secrets required.**

---

### 3. Release (release.yml)

**Trigger:** 
- Tag push (`v*.*.*`)
- Manual workflow dispatch with version input

**Steps:**
1. Extract version from tag or input
2. Select latest Xcode
3. Install Developer ID certificate (optional)
4. Archive & export .app
5. Notarize app (optional, if credentials exist)
6. Create distributable zip
7. Generate SHA-256 checksums
8. Generate changelog from git log
9. Create GitHub Release with artifacts

---

## Required Secrets

### For Signing & Notarization

Store these in GitHub repo settings under **Settings > Secrets and variables > Actions**:

| Secret | Description | Required? |
|--------|-------------|-----------|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` certificate | Optional* |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the `.p12` file | If cert exists |
| `APPLE_ID` | Apple ID for notarization | Optional* |
| `APPLE_ID_PASSWORD` | App-specific password | If notarizing |
| `TEAM_ID` | Apple Team ID | If notarizing |

*Signing and notarization are optional. Releases will still build unsigned if certificates aren't configured.

### How to Create Secrets

1. **Extract certificate to Base64:**
   ```bash
   base64 -i ~/path/to/certificate.p12 | pbcopy
   ```

2. **Generate App-Specific Password (Apple ID):**
   - Go to appleid.apple.com > Security > App-specific passwords
   - Create new password for "GitHub Actions"

3. **Find Team ID:**
   - Xcode > Settings > Accounts > Apple ID
   - Click Team dropdown → Team ID is shown

---

## Release Workflow

### Via Git Tag (Automatic)

```bash
# Bump version and tag
git tag v1.0.0
git push origin v1.0.0
# → Release workflow triggers automatically
```

### Via Manual Trigger

Go to **Actions > Release > Run workflow** and input version (e.g., `1.0.0`).

---

## Artifacts

Releases produce:
- **lsom.zip** — Notarized app bundle
- **checksums-sha256.txt** — SHA-256 hash for verification

---

## Self-Hosted Runner

The runner `mikes-macbook` must have:
- ✅ GitHub Actions Runner installed & configured
- ✅ Xcode installed
- ✅ SwiftLint (optional, for lint.yml)
- ✅ codesign tools available

**Status:** Check runner at **Settings > Runners**.

---

## Troubleshooting

### "No Xcode found"
- Ensure Xcode is installed in `/Applications/Xcode*.app`
- Check: `ls -d /Applications/Xcode*.app`

### "Certificate not found"
- Verify `DEVELOPER_ID_CERTIFICATE_BASE64` is set in Secrets
- Re-encode if certificate changed: `base64 -i cert.p12 | pbcopy`

### "Notarization failed"
- Check `APPLE_ID_PASSWORD` is an **app-specific password**, not your Apple ID password
- Verify Team ID matches certificate

### Build hangs
- Increase `timeout-minutes` in workflow YAML
- Check runner logs: **Settings > Runners > mikes-macbook > View logs**

---

## Industry Standards Applied

✅ **Separation of concerns** — Build, lint, and release are separate workflows  
✅ **Self-hosted runner** — Ensures consistent macOS environment  
✅ **Code signing** — Optional but configured for Developer ID  
✅ **Notarization** — Apple gatekeeper compliance  
✅ **Artifact management** — Checksums for integrity verification  
✅ **Changelog generation** — Automated from git history  
✅ **Concurrency control** — Cancels in-progress builds on new pushes  
✅ **Cleanup** — Temporary keychains deleted after build  

---

**Last updated:** 2026-02-09
