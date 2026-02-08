# Manual Test Checklist – LSoM

This checklist is for quick end‑to‑end verification of the app after code changes.

## 1. Basic run from Xcode

- Open `lsom.xcodeproj` and select the **lsom** scheme.
- Press `Cmd+R` to run.
- Confirm:
  - A mouse icon appears in the menu bar.
  - The status item shows a numeric battery percentage when the Logitech receiver is connected.

## 2. Popover behaviour

- Click the menu bar icon.
- Verify the popover shows:
  - Large `NN%` battery value.
  - A status line such as “Battery status: Good”.
  - A relative "Updated … ago" timestamp after a refresh.
- Click **Refresh now** and confirm the value updates if the battery has changed.

## 3. Debug tools

- With a Debug build, click **Log HID details**.
- In Xcode’s console, confirm HID‑level logs appear under the `lsom/hid:` prefix.

## 4. Receiver unplug / replug

- Unplug the Logitech receiver.
- After a refresh:
  - Status item clears the percentage or shows `–`.
  - Popover status line changes to “Receiver not found”.
- Plug the receiver back in and click **Refresh now**.
- Confirm the percentage and status return without restarting the app.

## 5. Permissions flow

- If HID access fails due to TCC (Input Monitoring), open **Settings… → Permissions**.
- Click **Open Input Monitoring…** and enable lsom in System Settings.
- Return to the app and verify that refreshing now succeeds.

