# Xcode Cloud Setup Guide for lsom

> Comprehensive step-by-step guide for setting up CI/CD with Xcode Cloud.

---

## Table of Contents

1. [Prerequisites Checklist](#prerequisites-checklist)
2. [Step 1: Link GitHub to Xcode Cloud](#step-1-link-github-to-xcode-cloud)
3. [Step 2: Create Build Workflow](#step-2-create-build-workflow-runs-on-every-push)
4. [Step 3: Create Test Workflow](#step-3-create-test-workflow-runs-on-every-push)
5. [Step 4: Create Release Workflow](#step-4-create-release-workflow-runs-on-version-tags)
6. [Step 5: Configure Post-Build Actions](#step-5-configure-post-build-actions-optional)
7. [Step 6: First Test](#step-6-first-test)
8. [Step 7: Test Release Build](#step-7-test-release-build)
9. [Troubleshooting](#troubleshooting)
10. [Reference Commands](#reference-commands)

---

## Prerequisites Checklist

Before starting, ensure you have all of the following:

- [ ] **Apple Developer Account** with an active membership
  - Team ID: `DW97QZ7F3B`
  - Must have Admin or App Manager role
  - Verify at [developer.apple.com/account](https://developer.apple.com/account)
- [ ] **GitHub Account** with admin access to the `lsom` repository
  - Repository: `mikezamayias/budget-coach` (or the correct repo name)
  - Admin access is required to install the Xcode Cloud GitHub App
- [ ] **Xcode 15+** installed locally
  - Xcode Cloud configuration can also be done via the web dashboard, but Xcode provides the most seamless experience
- [ ] **lsom.xcodeproj** with the `lsom` scheme properly configured
  - The scheme must be marked as **Shared** (check in Xcode → Product → Scheme → Manage Schemes → ensure "Shared" checkbox is ticked)
  - The scheme file should be committed to the repository

---

## Step 1: Link GitHub to Xcode Cloud

### Via Apple Developer Portal (Web)

1. Navigate to [developer.apple.com](https://developer.apple.com) and sign in
2. Go to **Xcode Cloud** in the left sidebar
3. Click **"Connect Repository"** (or "Get Started" if this is your first time)
4. Select **GitHub** as your source control provider
5. Click **"Authorize"** — this will redirect you to GitHub
6. On GitHub, authorize the **Xcode Cloud** GitHub App
   - Apple will install a GitHub App on your account/organization
   - Grant access to the `mikezamayias/budget-coach` repository (or all repositories if preferred)
7. Back in the Apple Developer portal, select the repository from the list
8. Confirm the connection

### Via Xcode (Alternative)

1. Open the `lsom` project in Xcode
2. Navigate to **Product → Xcode Cloud → Create Workflow…**
3. Xcode will prompt you to connect your source control provider
4. Follow the GitHub authorization flow
5. Select the correct repository

### Verifying the Connection

- In the Apple Developer portal under Xcode Cloud, you should see your repository listed
- On GitHub, go to **Settings → Integrations → Applications** and verify the Xcode Cloud app is installed with access to the correct repository

---

## Step 2: Create Build Workflow (Runs on Every Push)

This workflow compiles the project on every push to catch build errors early.

### Configuration

1. In the Xcode Cloud dashboard (or Xcode), click **"Create Workflow"**
2. Configure the following settings:

| Setting | Value |
|---|---|
| **Workflow Name** | `Build (Debug)` |
| **Description** | Builds the project on every push to verify compilation |
| **Repository** | `mikezamayias/budget-coach` |

### Start Conditions

| Setting | Value |
|---|---|
| **Trigger** | Branch Changes |
| **Source Branch** | All Branches (or specify `main`, `develop`, etc.) |
| **Auto-cancel builds** | Enabled (recommended — cancels superseded builds) |

### Environment

| Setting | Value |
|---|---|
| **Xcode Version** | Latest Release (or pin to a specific version like 15.x) |
| **macOS Version** | Latest Release |

### Actions

| Setting | Value |
|---|---|
| **Action Type** | Build |
| **Scheme** | `lsom` |
| **Platform** | macOS |
| **Configuration** | Debug |

### Post-Actions

- None required for this workflow

3. Click **"Save"**

---

## Step 3: Create Test Workflow (Runs on Every Push)

This workflow runs your test suite on every push to catch regressions.

### Configuration

1. Click **"Create Workflow"**
2. Configure the following settings:

| Setting | Value |
|---|---|
| **Workflow Name** | `Test` |
| **Description** | Runs the test suite on every push |
| **Repository** | `mikezamayias/budget-coach` |

### Start Conditions

| Setting | Value |
|---|---|
| **Trigger** | Branch Changes |
| **Source Branch** | All Branches |
| **Auto-cancel builds** | Enabled |

### Environment

| Setting | Value |
|---|---|
| **Xcode Version** | Latest Release |
| **macOS Version** | Latest Release |

### Actions

| Setting | Value |
|---|---|
| **Action Type** | Test |
| **Scheme** | `lsom` |
| **Platform** | macOS |
| **Configuration** | Debug |

### Post-Actions

- None required for this workflow

3. Click **"Save"**

> **Tip:** If your tests are fast, you can combine Build and Test into a single workflow. However, separate workflows give clearer pass/fail signals in your GitHub status checks.

---

## Step 4: Create Release Workflow (Runs on Version Tags)

This workflow creates a release build when you push a version tag (e.g., `v1.0.0`).

### Configuration

1. Click **"Create Workflow"**
2. Configure the following settings:

| Setting | Value |
|---|---|
| **Workflow Name** | `Release` |
| **Description** | Creates a release archive when a version tag is pushed |
| **Repository** | `mikezamayias/budget-coach` |

### Start Conditions

| Setting | Value |
|---|---|
| **Trigger** | Tag Changes |
| **Tag Pattern** | `v*.*.*` |
| **Auto-cancel builds** | Disabled (you want every tagged release to complete) |

### Environment

| Setting | Value |
|---|---|
| **Xcode Version** | Latest Release (or pin for reproducibility) |
| **macOS Version** | Latest Release |

### Actions

| Setting | Value |
|---|---|
| **Action Type** | Archive |
| **Scheme** | `lsom` |
| **Platform** | macOS |
| **Configuration** | Release |

### Code Signing

| Setting | Value |
|---|---|
| **Signing Style** | Automatic |
| **Team** | `DW97QZ7F3B` |
| **Distribution Method** | Developer ID (for direct distribution) or App Store (for Mac App Store) |

### Notarization

| Setting | Value |
|---|---|
| **Notarize** | Enabled (recommended if distributing outside the App Store) |

> **Note:** Notarization is handled automatically by Xcode Cloud when using Developer ID distribution. The app will be submitted to Apple's notary service, and Xcode Cloud will staple the notarization ticket to the archive.

### Post-Actions

- Optionally configure artifact storage or deployment (see Step 5)

3. Click **"Save"**

---

## Step 5: Configure Post-Build Actions (Optional)

### GitHub Releases Integration

After your workflows are created, you can enhance the Release workflow with GitHub integration:

1. **Xcode Cloud ci_scripts:** Create a `ci_scripts/` directory in your project root with post-build scripts:

   ```
   lsom/
   ├── ci_scripts/
   │   ├── ci_post_clone.sh      # Runs after cloning
   │   ├── ci_post_xcodebuild.sh # Runs after build/archive
   │   └── ci_pre_xcodebuild.sh  # Runs before build
   └── lsom.xcodeproj/
   ```

2. **Example `ci_post_xcodebuild.sh` for GitHub Releases:**

   ```bash
   #!/bin/bash
   set -e

   # Only run for the Release workflow archive action
   if [ "$CI_WORKFLOW" = "Release" ] && [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
       echo "Release archive completed successfully"
       echo "Tag: $CI_TAG"
       echo "Build Number: $CI_BUILD_NUMBER"
       
       # To create GitHub Releases automatically, you would need:
       # 1. A GitHub Personal Access Token stored as an Xcode Cloud environment variable
       # 2. The GitHub CLI (gh) or curl to call the GitHub API
       #
       # Example (requires GITHUB_TOKEN environment variable):
       # curl -X POST \
       #   -H "Authorization: token $GITHUB_TOKEN" \
       #   -H "Accept: application/vnd.github.v3+json" \
       #   "https://api.github.com/repos/mikezamayias/budget-coach/releases" \
       #   -d "{\"tag_name\":\"$CI_TAG\",\"name\":\"$CI_TAG\",\"draft\":false,\"prerelease\":false}"
   fi
   ```

3. **Make the script executable:**
   ```bash
   chmod +x ci_scripts/ci_post_xcodebuild.sh
   ```

4. **Adding Environment Variables (for GitHub token):**
   - In Xcode Cloud workflow settings → Environment Variables
   - Add `GITHUB_TOKEN` with your Personal Access Token value
   - Mark it as **Secret** so it's not exposed in logs

> **Note:** GitHub Release creation from Xcode Cloud requires additional configuration. Consider whether this complexity is worth it versus manually creating releases or using a separate GitHub Action triggered by the tag.

---

## Step 6: First Test

### Trigger the Build & Test Workflows

1. Make a small commit to any branch:
   ```bash
   cd /Users/mzamagias/Developer/Swift/lsom
   git add .
   git commit -m "ci: verify Xcode Cloud workflows"
   git push origin main
   ```

2. **Monitor the build:**
   - **Via Web:** Go to [developer.apple.com](https://developer.apple.com) → Xcode Cloud → your product
   - **Via Xcode:** Open the project → Report Navigator (⌘9) → Cloud tab
   - You should see both the "Build (Debug)" and "Test" workflows trigger

3. **Check build logs:**
   - Click on the running/completed build
   - Review the build log for any errors or warnings
   - Verify all steps completed successfully

4. **Verify GitHub integration:**
   - Go to your repository on GitHub
   - Check the latest commit — you should see status checks from Xcode Cloud
   - Green checkmarks ✅ indicate successful builds

### Expected Outcome

- ✅ "Build (Debug)" workflow completes successfully
- ✅ "Test" workflow completes and all tests pass
- ✅ GitHub commit shows passing status checks

---

## Step 7: Test Release Build

### Trigger the Release Workflow

1. **Create and push a beta tag:**
   ```bash
   cd /Users/mzamagias/Developer/Swift/lsom
   git tag v1.0.0-beta
   git push origin v1.0.0-beta
   ```

2. **Monitor the Release workflow:**
   - Go to Xcode Cloud dashboard
   - The "Release" workflow should trigger automatically
   - This build will take longer due to archiving and notarization

3. **Verify the results:**
   - ✅ Archive succeeds
   - ✅ Code signing completes with team `DW97QZ7F3B`
   - ✅ Notarization succeeds (if enabled)
   - ✅ GitHub Release is created (if post-build script is configured)

4. **Download the artifact:**
   - In Xcode Cloud dashboard, click on the completed Release build
   - Download the archive/artifact
   - Verify the app launches and is properly signed

### Clean Up Beta Tag (Optional)

If the beta was just for testing:
```bash
git tag -d v1.0.0-beta
git push origin --delete v1.0.0-beta
```

---

## Troubleshooting

### Build Failed

**Symptoms:** Build workflow shows a red ❌

**Solutions:**
- **Check build logs** in Xcode Cloud dashboard for the specific error
- **Missing dependencies:** Ensure all Swift Package Manager dependencies are properly declared in `Package.resolved` (committed to the repo)
- **Signing issues:** Verify your team ID (`DW97QZ7F3B`) is correctly configured and your Apple Developer account is active
- **Xcode version mismatch:** Pin the Xcode version in your workflow if you need a specific version
- **Missing scheme:** Ensure the `lsom` scheme is shared and committed (see Prerequisites)

### Notarization Timed Out

**Symptoms:** Release workflow hangs at notarization step

**Solutions:**
- Xcode Cloud will **retry automatically** — wait for the retry
- Check [Apple System Status](https://developer.apple.com/system-status/) for notary service issues
- If persistent, try triggering the workflow again

### Scheme Not Found

**Symptoms:** Error saying the scheme `lsom` cannot be found

**Solutions:**
1. Open the project in Xcode
2. Go to **Product → Scheme → Manage Schemes**
3. Ensure `lsom` scheme exists and the **Shared** checkbox is checked
4. Commit and push the `.xcscheme` file:
   ```bash
   git add lsom.xcodeproj/xcshareddata/xcschemes/lsom.xcscheme
   git commit -m "fix: share lsom scheme for Xcode Cloud"
   git push
   ```

### Can't Connect GitHub

**Symptoms:** Xcode Cloud can't see your repository or can't access it

**Solutions:**
1. Go to GitHub → **Settings → Integrations → Applications**
2. Find the **Xcode Cloud** app
3. Click **Configure** and verify it has access to the correct repository
4. If the app isn't installed, re-initiate the connection from Xcode Cloud
5. Ensure you have **admin** access to the repository

### Environment Variables Not Available

**Symptoms:** Scripts can't access custom environment variables

**Solutions:**
- Verify the variable is set in the correct workflow's settings
- Secret variables are not printed in logs — use `echo "VAR is set: $([ -n "$VAR" ] && echo yes || echo no)"` to check
- Variable names are case-sensitive

### Build Passes Locally but Fails in Xcode Cloud

**Symptoms:** Works on your machine but not in CI

**Solutions:**
- Check Xcode version differences between local and CI
- Ensure all dependencies are committed (`Package.resolved`)
- Xcode Cloud uses a clean environment — no cached builds or local configurations
- Check for hardcoded paths or local-only configurations

---

## Reference Commands

### Git Tags (for Release Workflow)

```bash
# Tag a release and push
git tag v1.0.0
git push origin v1.0.0

# Tag with a message (annotated tag)
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# List all tags
git tag

# List tags matching a pattern
git tag -l "v1.*"

# Delete a local tag
git tag -d v1.0.0

# Delete a remote tag
git push origin --delete v1.0.0

# Delete both local and remote
git tag -d v1.0.0 && git push origin --delete v1.0.0
```

### Xcode Cloud Environment Variables

These are automatically available in `ci_scripts/`:

| Variable | Description |
|---|---|
| `CI` | Always `TRUE` in Xcode Cloud |
| `CI_WORKFLOW` | Name of the current workflow |
| `CI_XCODEBUILD_ACTION` | Current action (`build`, `test`, `archive`) |
| `CI_BUILD_NUMBER` | Auto-incrementing build number |
| `CI_TAG` | Git tag that triggered the build (if applicable) |
| `CI_BRANCH` | Branch name |
| `CI_COMMIT` | Commit SHA |
| `CI_PRODUCT` | Product name |
| `CI_ARCHIVE_PATH` | Path to the archive (archive action only) |

### Useful Xcode Commands

```bash
# List available schemes
xcodebuild -list -project lsom.xcodeproj

# Build locally (same as CI would)
xcodebuild -scheme lsom -configuration Debug build

# Run tests locally
xcodebuild -scheme lsom -configuration Debug test

# Archive locally
xcodebuild -scheme lsom -configuration Release archive -archivePath ./build/lsom.xcarchive
```

---

## Workflow Summary

| Workflow | Trigger | Action | Configuration |
|---|---|---|---|
| **Build (Debug)** | Push to any branch | Build | Debug |
| **Test** | Push to any branch | Test | Debug |
| **Release** | Tag matching `v*.*.*` | Archive + Notarize | Release |

---

*Last updated: 2026-02-08*
