# Xcode Cloud Setup — lsom

Xcode Cloud is now the **single source of truth** for all CI/CD.

> GitHub Actions workflows have been archived to `.github/workflows.archived/` for reference.

## Overview

| Workflow | Trigger | Action |
|----------|---------|--------|
| **Build** | Push to any branch | Build (Debug) + SwiftLint |
| **Test** | Push to any branch | Run unit tests |
| **Release** | Tag matching `v*.*.*` | Archive → Sign → Notarize → Distribute |

## How It Works

Xcode Cloud workflows are configured in **Xcode** (Product → Xcode Cloud) or via
[App Store Connect](https://appstoreconnect.apple.com). They are **not** YAML files
in the repo. The only repo-level customization is through `ci_scripts/`:

```
ci_scripts/
├── ci_post_clone.sh       # Install tools (SwiftLint)
├── ci_pre_xcodebuild.sh   # Run linting before build
└── ci_post_xcodebuild.sh  # Log archive info, checksums
```

## Initial Setup (One-Time, in Xcode)

### 1. Connect GitHub Repository

1. Open `lsom.xcodeproj` in Xcode
2. Go to **Product → Xcode Cloud → Create Workflow…**
3. Sign in with your Apple ID (must have Apple Developer Program membership)
4. Grant Xcode Cloud access to the GitHub repo `mzamagias/lsom`
5. Xcode will install a GitHub App for webhook integration automatically

### 2. Create "Build" Workflow

1. **Product → Xcode Cloud → Manage Workflows… → + (Create Workflow)**
2. Name: `Build`
3. **Start Conditions:**
   - Source Control: Branch Changes → All Branches
4. **Environment:**
   - Xcode Version: Latest Release
   - macOS Version: Latest
5. **Actions:**
   - Action: Build
   - Scheme: `lsom`
   - Platform: macOS
   - Configuration: Debug
6. Save

### 3. Create "Test" Workflow

1. Create another workflow named `Test`
2. **Start Conditions:**
   - Source Control: Branch Changes → All Branches
3. **Actions:**
   - Action: Test
   - Scheme: `lsom`
   - Platform: macOS
4. Save

### 4. Create "Release" Workflow

1. Create another workflow named `Release`
2. **Start Conditions:**
   - Source Control: Tag Changes → Custom Tag Pattern: `v*.*.*`
3. **Environment:**
   - Xcode Version: Latest Release
   - macOS Version: Latest
4. **Actions:**
   - Action: Archive
   - Scheme: `lsom`
   - Platform: macOS
   - Configuration: Release
5. **Post-Actions:**
   - Notify (Slack/email as desired)
6. **Distribution (optional):**
   - If distributing via Mac App Store: Add TestFlight distribution
   - If distributing via Developer ID: Export and notarize automatically
7. Save

### 5. Code Signing

Xcode Cloud handles code signing **automatically**:
- Uses your Apple Developer team: `DW97QZ7F3B`
- Bundle ID: `com.mikezamagias.lsom`
- Signing style: Automatic
- No manual certificates or provisioning profiles needed
- Xcode Cloud manages cloud-based signing keys

### 6. GitHub Release Creation

Xcode Cloud doesn't natively create GitHub Releases. Options:

**Option A: Manual (recommended for now)**
After Xcode Cloud archives and notarizes, download the artifact from
App Store Connect and create the GitHub Release manually:
```bash
# After Xcode Cloud archive succeeds:
gh release create v1.0.0 \
  --title "lsom v1.0.0" \
  --notes-file docs/CHANGELOG.md \
  lsom.zip checksums-sha256.txt
```

**Option B: Webhook + GitHub Action (hybrid)**
Keep a minimal GitHub Action that triggers on Xcode Cloud completion webhook
to create the release. (See `.github/workflows.archived/release.yml` for reference.)

## Day-to-Day Usage

### Trigger a Build
```bash
git push origin main        # Any push triggers Build + Test workflows
```

### Create a Release
```bash
# 1. Update version in Xcode target settings
# 2. Update docs/CHANGELOG.md
# 3. Commit and tag:
git tag v1.0.0
git push origin v1.0.0      # Triggers Release workflow
```

### Monitor Builds
- **In Xcode:** Window → Cloud Builds (⌘⌥C)
- **In App Store Connect:** [appstoreconnect.apple.com/teams/.../xcode-cloud](https://appstoreconnect.apple.com)

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Build fails on clone | Check GitHub App permissions in repo Settings → Integrations |
| Code signing error | Verify team ID in Xcode → Signing & Capabilities |
| SwiftLint not found | `ci_post_clone.sh` installs it; check Homebrew availability |
| Workflow not triggering | Verify Start Conditions in Xcode Cloud workflow settings |
| Archive not notarized | Ensure Apple ID has notarization entitlement; check post-archive distribution settings |

## Pricing

Xcode Cloud includes **25 compute hours/month free** with Apple Developer Program membership.
For lsom's needs (small project, ~1 min builds), this is more than sufficient.
