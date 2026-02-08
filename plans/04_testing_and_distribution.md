# Testing & Distribution Plan – Quality, Signing, and Shipping

## Goals

- Ensure HID++ logic is correct and stays correct as the app evolves.
- Exercise each Clean Architecture layer in isolation (Domain/Application, Infrastructure, Presentation).
- Provide a clear workflow for building, signing, and running the `.app` outside Xcode, following current macOS guidelines.
- Prepare the project for eventual notarization and sharing (even if only privately).

---

## Plan

### 1. Unit-style tests for HID decoding and domain logic

- [ ] Add a test target `lsomTests` in Xcode.
- [ ] Extract pure functions from `LogitechHIDService` and Domain types, such as:
  - [ ] `func parseUnifiedBatteryStatus(_ bytes: [UInt8]) -> Int?`
  - [ ] `func parseRootGetFeature(_ bytes: [UInt8]) -> (index: UInt8, type: UInt8)?`
- [ ] Write tests that:
  - [ ] Feed the known good Python sample response:
    - [ ] `11 01 06 10 63 08 00 ...`
    - [ ] Assert that `parseUnifiedBatteryStatus` returns `99`.
  - [ ] Feed synthetic Root.GetFeature replies and assert the decoded feature index and type.
- [ ] Keep these tests focused and fast—no real HID access inside tests.
- [ ] For Application‑level types (e.g. use cases / coordinators), inject fake `BatteryService` implementations to keep tests deterministic.

### 2. Manual integration test checklist

- [ ] Create `docs/manual-test-checklist.md` with steps:
  - [ ] Start app from Xcode (`Cmd+R`).
  - [ ] Verify:
    - [ ] Status item shows icon + correct battery percent.
    - [ ] Popover shows matching “Battery: NN%”.
    - [ ] “Refresh now” updates the value (if battery has changed).
    - [ ] “Log” produces expected HID debug output.
  - [ ] Unplug receiver → confirm:
    - [ ] Status item clears or shows “—”.
    - [ ] Popover shows “Receiver not found” or similar.
  - [ ] Replug receiver → confirm battery returns without restarting app.

### 3. Building and signing the app (best practice)

- [ ] Confirm Xcode target settings follow Apple’s current recommendations:
  - [ ] `Bundle Identifier` is stable (`com.mikezamagias.lsom`).
  - [ ] `Team` is set to your Apple Developer account (or `Sign to Run Locally`).
  - [ ] `Signing Certificate` is `Developer ID` / `Apple Development` appropriate for your distribution.
- [ ] Archive and export:
  - [ ] `Product → Archive`.
  - [ ] Export a signed `.app` or `.dmg`.
- [ ] Copy the resulting `lsom.app` to `~/Applications`:
  - [ ] Double-click to verify:
    - [ ] The menu bar item appears.
    - [ ] HID access and battery reads still work outside Xcode.
    - [ ] No unexpected permission prompts beyond what you expect (Input Monitoring).

### 4. Notarization (optional, but recommended for sharing)

- [ ] If you plan to distribute the app:
  - [ ] Configure notarization in Xcode’s Organizer or via `xcrun notarytool`.
  - [ ] Ensure entitlements / Info.plist entries (LSUIElement, usage descriptions) are correct.
  - [ ] Submit and verify notarization results.
- [ ] Document the steps in `docs/release-process.md` so future updates follow the same path.

### 5. Versioning and About panel

- [ ] Add semantic versioning to the project (`1.0.0`, `1.1.0`, etc.).
- [ ] Make sure `CFBundleShortVersionString` and `CFBundleVersion` are kept in sync.
- [ ] Implement a simple “About lsom” view in Settings:
  - [ ] Show app name, version, build number.
  - [ ] Optionally a short description and a link to the project repository or website.

---

## End State

When this plan is completed:

- Battery parsing and HID++ decoding are covered by unit tests.
- You have a repeatable manual test checklist for new builds.
- You can build and run a signed `lsom.app` outside Xcode with confidence.
- The project is ready for notarization and external distribution if you choose to share it.
