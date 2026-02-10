# lsom v1.0.0 Notarization Guide

Apple requires all macOS software distributed outside the App Store to be notarized. This ensures the software meets security requirements and hasn't been tampered with.

## Prerequisites

1. **Apple Developer Account** (free)
2. **Apple ID** with app notarization credentials
3. **Xcode** installed with Command Line Tools
4. **DMG file** already built (`lsom-v1.0.0.dmg`)

## Notarization Steps

### Step 1: Create App-Specific Password

Since your Apple ID likely has 2FA enabled, you need an app-specific password:

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Security → **Generate password** (for Xcode)
4. Name it something like "lsom-notarization"
5. Copy the generated password (you'll use it in Step 3)

### Step 2: Store Credentials in Keychain

Store your Apple ID and app-specific password securely:

```bash
xcrun notarytool store-credentials "lsom-notarization" \
  --apple-id your-email@icloud.com \
  --team-id YOUR_TEAM_ID \
  --password "your-app-specific-password"
```

**Replace:**
- `your-email@icloud.com` with your Apple ID email
- `YOUR_TEAM_ID` with your Developer Team ID (find it on developer.apple.com)
- `your-app-specific-password` with the 16-character password from Step 1

### Step 3: Notarize the DMG

```bash
xcrun notarytool submit "/tmp/lsom-v1.0.0.dmg" \
  --keychain-profile "lsom-notarization" \
  --wait
```

**Output will show:**
```
Submitting file for notarization: /tmp/lsom-v1.0.0.dmg
Waiting for notarization response...
  id: <submission-id>
  status: Accepted
  message: The software was successfully notarized.
```

### Step 4: Staple Notarization Ticket to DMG (Optional but Recommended)

```bash
xcrun stapler staple "/tmp/lsom-v1.0.0.dmg"
```

This embeds the notarization ticket directly in the DMG, so internet isn't required to verify on first launch.

### Step 5: Verify Notarization

```bash
spctl -a -v -t open --context context=execute "/tmp/lsom-v1.0.0.dmg"
```

**Expected output:**
```
/tmp/lsom-v1.0.0.dmg: accepted
source=Notarized Developer ID
```

## If Notarization Is Rejected

### Review Rejection Details

```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "lsom-notarization"
```

### Common Issues & Fixes

**Issue: "The executable contains a signature invalid for use on macOS"**
- **Fix:** Rebuild with current Xcode version and valid signing certificate
  ```bash
  xcodebuild build -scheme lsom -configuration Release
  ```

**Issue: "Code signature is not valid"**
- **Fix:** Ensure code signing identity is correct in Xcode
  - Xcode → Targets → Build Settings → Code Signing Identity
  - Set to your Apple Developer certificate

**Issue: "The certificate is not valid"**
- **Fix:** Update your Apple Developer certificate
  - Xcode → Preferences → Accounts → Download Manual Profiles

## Automated Notarization Script

For future releases, use this script to automate notarization:

```bash
#!/bin/bash
# notarize.sh

set -e

DMG_PATH="${1:?Please provide DMG path}"
PROFILE_NAME="lsom-notarization"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH"
    exit 1
fi

echo "📦 Notarizing: $DMG_PATH"
echo ""

# Submit for notarization
RESULT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$PROFILE_NAME" \
    --wait 2>&1)

# Extract status
if echo "$RESULT" | grep -q "status: Accepted"; then
    echo "✅ Notarization successful!"
    echo ""
    
    # Staple ticket
    echo "📌 Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    
    # Verify
    echo ""
    echo "🔍 Verifying..."
    spctl -a -v -t open --context context=execute "$DMG_PATH"
    
    echo ""
    echo "✨ DMG ready for release!"
else
    echo "❌ Notarization failed:"
    echo "$RESULT"
    exit 1
fi
```

**Usage:**
```bash
chmod +x notarize.sh
./notarize.sh /tmp/lsom-v1.0.0.dmg
```

## GitHub Release Integration

Once notarized, upload to GitHub Releases:

```bash
# Install gh CLI (if not already installed)
brew install gh

# Create release with DMG
gh release create v1.0.0 \
  --title "lsom v1.0.0" \
  --notes-file RELEASE_NOTES_v1.0.0.md \
  /tmp/lsom-v1.0.0.dmg

# Or upload DMG to existing release
gh release upload v1.0.0 /tmp/lsom-v1.0.0.dmg
```

## Notes

- Notarization takes 1-5 minutes (usually 2-3)
- You need internet to notarize (submits to Apple servers)
- Notarization ticket is valid for ~1 year
- Stapling is optional but recommended for offline use
- Keep the `--keychain-profile` password secure

## Troubleshooting

**"xcrun: error: unable to find utility"**
- Install Xcode Command Line Tools:
  ```bash
  xcode-select --install
  ```

**"keychain error: Item not found"**
- Re-run the credential storage command from Step 2
- Ensure profile name matches (`lsom-notarization`)

**"Invalid session"**
- Your App-Specific Password may have changed
- Re-create and store credentials

## References

- [Apple Developer: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [xcrun notarytool Manual](https://manpages.org/xcrun-notarytool)
- [Stapler Documentation](https://manpages.org/xcrun-stapler)

---

**Once notarization is complete, you're ready to distribute on ProductHunt, GitHub Releases, and eventually Homebrew Cask!** 🚀
