# Release Process – lsom

## CI/CD

All CI/CD runs on **Xcode Cloud**. See [`XCODE_CLOUD_SETUP.md`](XCODE_CLOUD_SETUP.md) for full details.

> Previous GitHub Actions workflows are archived in `.github/workflows.archived/`.

## 1. Pre-release Checks

- Run through `docs/manual-test-checklist.md` on the latest commit.
- Ensure the status item shows the correct Logitech mouse battery value.
- Verify Settings:
  - "Launch at login" toggle works as expected.
  - Permission buttons open the right System Settings panes.
- Verify local build succeeds:
  ```bash
  xcodebuild build -project lsom.xcodeproj -scheme lsom -configuration Release -destination 'platform=macOS'
  ```

## 2. Versioning

- Decide a semantic version (e.g. `1.0.0`, `1.1.0`).
- In Xcode target settings for **lsom**:
  - Set **Marketing Version** (`CFBundleShortVersionString`) to the new version.
  - Bump **Current Project Version** (`CFBundleVersion`) as needed.
- Update `docs/CHANGELOG.md` with the release notes.

## 3. Tag and Push

```bash
git add -A
git commit -m "Release v1.0.0"
git tag v1.0.0
git push origin main --tags
```

This triggers the **Release** workflow in Xcode Cloud, which will:
- Archive the app (Release configuration)
- Code sign automatically (Apple Developer team DW97QZ7F3B)
- Notarize with Apple (automatic)

## 4. Monitor the Build

- **In Xcode:** Window → Cloud Builds (⌘⌥C)
- **In App Store Connect:** Xcode Cloud section

## 5. Create GitHub Release

After Xcode Cloud completes, download the notarized artifact and create the GitHub release:

```bash
gh release create v1.0.0 \
  --title "lsom v1.0.0" \
  --notes-file docs/CHANGELOG.md \
  lsom.zip checksums-sha256.txt
```

## 6. Post-Release

- Verify the GitHub Release page has the correct assets.
- Test the downloaded `.app` by running it from `~/Applications`.
- Confirm HID access works after granting Input Monitoring permission.
