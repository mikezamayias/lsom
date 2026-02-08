# lsom: Product Strategy & Testing

## 1. Testing Strategy (IOKit & HID++)

Since `lsom` interacts with physical Logitech hardware, automated testing is challenging. We will adopt a **Hardware Abstraction Layer (HAL)** approach.

### Architecture for Testability
Instead of calling `IOHIDDevice` directly, we define a protocol:

```swift
protocol HIDDeviceProtocol {
    func open() throws
    func close()
    func send(report: Data) throws
    func setInputReportCallback(_ callback: @escaping (Data) -> Void)
}
```

*   **Production Implementation:** Wraps `IOHIDDevice`.
*   **Test Implementation:** `MockHIDDevice`.
    *   Records sent reports (assertions).
    *   Simulates incoming reports (e.g., "Battery Level 50%" hex sequence) to test UI updates.

### Unit Tests
*   **Protocol Parsing:** Test the `HIDPlusPlus` parser with raw hex strings.
    *   Input: `10 01 0F ...` (Notification) -> Output: `BatteryLevel(50%)`.
*   **State Management:** Test that a "Device Disconnected" event correctly updates the `DeviceListModel`.

### Manual Testing Plan
*   **Device Matrix:** MX Master 3, MX Keys, G502 (if supported).
*   **OS Matrix:** macOS Sequoia (15.x), Sonoma (14.x).

## 2. Go-To-Market (GTM) Strategy

### Positioning
*   **Tagline:** "Unlock your Logitech gear on macOS. Native. Fast. Open."
*   **Value Prop:** No heavy Electron bloat (GHub), native SwiftUI feel, scriptable.

### Media Assets
1.  **Demo Video (30s):**
    *   Split screen: Camera on Mouse + Screen recording.
    *   Action: User clicks a custom button -> Mac executes a complex Shortcut instantly.
2.  **Screenshots:**
    *   Clean macOS window with vibrant device icons.
    *   "Dark Mode" variant.

### Distribution Channels
1.  **GitHub Releases:** `dmg` and `zip` (Notarized).
2.  **Homebrew:** `brew install --cask lsom`.
    *   *Action:* Create a tap `mikezamayias/homebrew-tap` first, then submit to `homebrew/cask` later.
3.  **Product Hunt:**
    *   Launch day: Tuesday or Wednesday (00:01 PST).
    *   First comment: "I built this because GHub uses 500MB RAM. lsom uses 15MB."

### Social Media (X/Twitter/LinkedIn)
*   **Thread:** "I reverse-engineered the Logitech HID++ protocol so you don't have to install 1GB of bloatware. Here is `lsom`."
*   **Visuals:** Hex dump screenshots vs. the clean SwiftUI interface.
