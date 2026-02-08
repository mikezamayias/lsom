# Code Review Report: lsom

**Date:** 2025-12-31
**Reviewer:** Claude Code
**Codebase:** ~3,800 lines of Swift across 17 files

## Executive Summary

The codebase is well-structured following Clean Architecture principles with clear layer separation. However, there are several code smells, outdated patterns, and opportunities to leverage modern Swift 5.9+ features.

---

## Critical Issues

### 1. Thread Safety Issues in `HIDFAPWaiter`

**Location:** `Infrastructure/LogitechHIDService.swift:15-23`

```swift
final class HIDFAPWaiter {
    var response: [UInt8]?
    var done: Bool = false
```

**Problem:** `HIDFAPWaiter` is accessed across threads (callback + main run loop) without synchronization. The `done` and `response` properties are mutated from a C callback.

**Fix:** Use `@unchecked Sendable` with explicit locking or use Swift's modern concurrency primitives:

```swift
final class HIDFAPWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var _response: [UInt8]?
    private var _done = false

    var response: [UInt8]? {
        get { lock.withLock { _response } }
        set { lock.withLock { _response = newValue } }
    }

    var done: Bool {
        get { lock.withLock { _done } }
        set { lock.withLock { _done = newValue } }
    }
}
```

---

### 2. Global C Callback with Unsafe Pointer Access

**Location:** `Infrastructure/LogitechHIDService.swift:26-47`

```swift
private let hidFAPInputCallback: IOHIDReportCallback = { ... }
```

**Problem:** The callback uses `Unmanaged<HIDFAPWaiter>.fromOpaque()` which is inherently unsafe and could crash if the waiter is deallocated before the callback fires.

**Recommendation:** Ensure the waiter's lifetime extends beyond the callback registration, or use a safer pattern with retained references.

---

### 3. Synchronous HID I/O Blocking the Run Loop

**Location:** `Infrastructure/LogitechHIDService.swift:452-456`

```swift
while !waiter.done && Date().timeIntervalSinceReferenceDate < deadline {
    CFRunLoopRunInMode(mode, 0.05, false)
}
```

**Problem:** Spinning the run loop with polling is inefficient and can cause UI jank if called on the main thread.

**Recommendation:** Consider using async/await with continuations or dispatch semaphores on a background queue.

---

## High Priority Issues

### 4. Massive God Class: `LogitechHIDService` (2,487 lines)

**Location:** `Infrastructure/LogitechHIDService.swift`

**Problem:** This single class handles:
- HID manager lifecycle
- FAP protocol
- RAP protocol
- Battery reading
- DPI settings
- Polling rate settings
- Button mappings
- Onboard profiles
- Device name lookup
- Feature caching
- Connection/disconnection events

**Recommendation:** Split into focused classes:
- `HIDTransport` - low-level I/O
- `HIDPPCommandExecutor` - FAP/RAP protocol
- `UnifiedBatteryReader`
- `DPIController`
- `PollingRateController`
- `ButtonMappingController`

---

### 5. IOKit Import in Domain Layer

**Location:** `Domain/BatteryService.swift:10-11`

```swift
import IOKit
import IOKit.hid
```

**Problem:** The Domain layer should contain only business logic, not infrastructure imports. `IOKit` imports violate the clean architecture dependency rule.

**Fix:** Remove IOKit imports from `BatteryService.swift`. The error types can use `Int32` instead of `IOReturn`:

```swift
case deviceOpenFailed(code: Int32)
```

---

### 6. `unowned` Reference Risk

**Location:** `Presentation/PopoverViewModel.swift:17`, `Presentation/SettingsView.swift:17`

```swift
private unowned let appDelegate: AppDelegate
```

**Problem:** Using `unowned` creates a crash risk if `AppDelegate` is deallocated before the ViewModel. While unlikely in this app structure, it's a code smell.

**Fix:** Use `weak` with proper optional handling, or pass the required closures/publishers instead of the entire AppDelegate.

---

### 7. Thread.detachNewThread() Mixed with Task.detached

**Location:** `Application/lsomApp.swift:226`

```swift
Thread.detachNewThread { [weak self] in
    // ...
    Task.detached {
        // ...
    }
    _ = semaphore.wait(timeout: .now() + 10)
}
```

**Problem:** Mixing `Thread.detachNewThread` with `Task.detached` inside it creates confusing threading semantics. Also uses deprecated `DispatchSemaphore` pattern inside async context.

**Recommendation:** Use a dedicated serial DispatchQueue or Swift Actor for HID operations:

```swift
actor HIDExecutor {
    func executeHIDOperation<T>(_ operation: () async throws -> T) async throws -> T {
        // Runs on dedicated actor
    }
}
```

---

## Medium Priority Issues

### 8. Missing `Sendable` Conformance on Protocols

**Locations:** `Domain/BatteryService.swift`, `Domain/MouseSettingsService.swift`

**Problem:** `ButtonControl`, `ButtonMapping`, `DPISensorInfo` etc. are marked `Sendable` but the protocols (`BatteryService`, `MouseSettingsService`) are not.

**Fix:** Add `Sendable` requirements:

```swift
protocol BatteryService: Sendable {
    func batteryPercentage() throws -> Int
}
```

---

### 9. Redundant Force Unwrapping

**Location:** `Infrastructure/LogitechHIDService.swift:2470`

```swift
if CFNumberGetValue((value as! CFNumber), .sInt32Type, &int32) {
```

**Problem:** Force cast `as!` can crash.

**Fix:** Use optional binding:

```swift
if let cfNumber = value as? CFNumber {
    CFNumberGetValue(cfNumber, .sInt32Type, &int32)
}
```

---

### 10. Excessive NSLog Usage

**Locations:** `Presentation/SettingsView.swift:147-171`, `Infrastructure/LogitechHIDService.swift:1172-1490`

```swift
NSLog("POLLING: [UI] applyPollingRate called - new=%d, previous=%d", rate, previousRate)
```

**Problem:** 50+ `NSLog` calls mixed with custom logging infrastructure. Inconsistent logging strategy.

**Recommendation:** Use OSLog consistently:

```swift
import os.log

private let logger = Logger(subsystem: "com.lsom", category: "HID")
logger.debug("Polling rate changed: \(rate)")
```

---

### 11. Singleton Anti-pattern

**Location:** `Infrastructure/HIDLogService.swift:14`

```swift
static let shared = HIDLogService()
```

**Problem:** Singletons make testing difficult and hide dependencies.

**Fix:** Inject `HIDLogService` through `AppEnvironment`:

```swift
final class AppEnvironment {
    let logService: HIDLogService
}
```

---

### 12. File Header Comment Mismatch

**Location:** `Infrastructure/LogitechHIDService.swift:1-6`

```swift
//  HIDDebugService.swift  // <-- Wrong filename in header
```

**Fix:** Update to match actual filename:

```swift
//  LogitechHIDService.swift
```

---

### 13. Dead Code / Debug Artifacts

**Location:** `Infrastructure/LogitechHIDService.swift:812-818`

```swift
// M O
// 6 6
// 7 2
// 5 7
// 8 3
//
```

**Problem:** Debug notes accidentally left in the code.

**Fix:** Remove dead comments.

---

### 14. Inconsistent Preview Patterns

**Location:** `Presentation/PopoverView.swift:444-518`

**Problem:** Duplicated `PopoverPreviewContainer` recreates the entire view hierarchy instead of using mock dependencies.

**Recommendation:** Create a mock `PopoverViewModel` for previews:

```swift
#if DEBUG
extension PopoverViewModel {
    static func preview(
        batteryPercent: Int? = 89,
        isConnected: Bool = true
    ) -> PopoverViewModel {
        // Return configured mock
    }
}
#endif
```

---

### 15. Disabled Logging Code

**Location:** `Infrastructure/LogitechHIDService.swift:57-68`

```swift
private func hidLog(_ message: @autoclosure () -> String) {
    // Temporarily disabled - use POLLING: logs instead
    // let msg = message()
    // ...
}
```

**Problem:** Commented-out logging code should either be removed or properly feature-flagged.

---

## Minor Issues / Style Improvements

### 16. Use Swift 5.9+ Features

**Observation Framework (macOS 14+):**

```swift
// Current:
@Published var lastBatteryPercent: Int?

// Modern (when targeting macOS 14+):
@Observable
final class AppDelegate {
    var lastBatteryPercent: Int?
}
```

**if/switch expressions:**

```swift
// Current:
let showPercentage = UserDefaults.standard.object(forKey: ...) == nil
    ? true
    : UserDefaults.standard.bool(forKey: ...)

// Modern:
let showPercentage = if UserDefaults.standard.object(forKey: ...) == nil {
    true
} else {
    UserDefaults.standard.bool(forKey: ...)
}
```

---

### 17. Magic Numbers Should Be Constants

**Location:** `Infrastructure/LogitechHIDService.swift:450, 667, etc.`

```swift
let timeout: TimeInterval = 0.5
let candidateIndexes: [UInt8] = [1, 2, 3, 4, 5, 6]
```

**Fix:** Move to the `HIDPP` enum:

```swift
private enum HIDPP {
    static let defaultTimeout: TimeInterval = 0.5
    static let maxDeviceIndex: UInt8 = 6
    static let deviceIndexRange: ClosedRange<UInt8> = 1...6
}
```

---

### 18. Inefficient Array Operations

**Location:** `Domain/HIDPPParsing.swift:183`

```swift
let unique = Array(Set(values)).sorted()
```

**Problem:** Creating a Set then converting back to Array is O(n) + O(n log n). Consider using `OrderedSet` from Swift Collections or inline deduplication.

---

### 19. Missing Access Control

Many types lack explicit access control modifiers, defaulting to `internal`. Consider:
- Mark protocols as `public` if they're part of the API
- Mark implementation details as `private` or `fileprivate`
- Mark classes as `final` when not designed for subclassing

---

### 20. Prepare for Typed Throws (Swift 6)

```swift
// Current:
func batteryPercentage() throws -> Int

// Swift 6 (when available):
func batteryPercentage() throws(LogitechHIDError) -> Int
```

---

### 21. Consider Using `@AppStorage` for UserDefaults

**Location:** `Application/lsomApp.swift`, `Presentation/SettingsView.swift`

```swift
// Current:
UserDefaults.standard.bool(forKey: UserDefaultsKey.showPercentageInMenuBar)

// Modern SwiftUI:
@AppStorage("ShowPercentageInMenuBar") var showPercentage = true
```

---

## Summary Table

| Priority | Count | Categories |
|----------|-------|------------|
| Critical | 3 | Thread safety, memory safety |
| High | 4 | Architecture, code organization |
| Medium | 8 | Logging, patterns, dead code |
| Minor | 6 | Swift modernization, style |

---

## Recommended Next Steps

### Immediate (Before Next Release)
1. Fix thread safety in `HIDFAPWaiter` with proper locking
2. Remove dead debug comments
3. Fix file header mismatch

### Short-term (Next Sprint)
1. Remove IOKit imports from Domain layer
2. Replace `unowned` with `weak` or dependency injection
3. Consolidate logging strategy (choose OSLog or custom, not both)

### Medium-term (Next Quarter)
1. Split `LogitechHIDService` into focused components
2. Inject `HIDLogService` instead of using singleton
3. Add unit tests for `HIDPPParsing` (already designed for testability)

### Long-term (Future Versions)
1. Adopt Observation framework when targeting macOS 14+
2. Prepare for Swift 6 typed throws
3. Consider using Swift Concurrency actors for HID operations

---

## Files Reviewed

| File | Lines | Notes |
|------|-------|-------|
| `Infrastructure/LogitechHIDService.swift` | ~2,487 | Needs splitting |
| `Presentation/SettingsView.swift` | ~1,060 | Clean, good previews |
| `Presentation/PopoverView.swift` | ~519 | Minor preview duplication |
| `Application/lsomApp.swift` | ~299 | Threading concerns |
| `Domain/HIDPPParsing.swift` | ~413 | Well-structured, testable |
| `Domain/MouseDeviceState.swift` | ~173 | Clean value type |
| `Domain/MouseSettingsService.swift` | ~141 | Good protocol design |
| `Infrastructure/HIDLogService.swift` | ~166 | Singleton pattern |
| `Domain/BatteryService.swift` | ~83 | IOKit import issue |
| `Infrastructure/SystemPermissionsService.swift` | ~55 | Clean |
| `Application/AppEnvironment.swift` | ~43 | Good DI container |
| `Domain/PermissionsServices.swift` | ~29 | Clean protocols |
| `Application/AutoRefreshInterval.swift` | ~28 | Clean enum |
