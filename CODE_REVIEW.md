# Code Review Report: lsom

**Date:** 2025-12-31
**Codebase:** ~3,800 lines of Swift across 17 files
**Reviewers:** Claude Opus 4.5, GPT 5.2 Codex, GPT 5.1 Codex Max
**Last Updated:** 2025-12-31 (18 of 18 issues resolved)

---

## Executive Summary

This report consolidates findings from three independent AI code reviews. The codebase follows Clean Architecture principles with clear layer separation, but all reviewers identified **critical thread safety issues** and opportunities to leverage modern Swift features.

### Issue Status

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | Thread safety in HIDFAPWaiter | Critical | ✅ Fixed |
| 2 | Mixed threading patterns | Critical | ✅ Fixed |
| 3 | God class (LogitechHIDService) | High | ✅ Fixed |
| 4 | IOKit import in Domain | High | ✅ Fixed |
| 5 | unowned reference risk | High | ✅ Fixed |
| 6 | Singleton anti-pattern | High | ✅ Fixed |
| 7 | Preview detection incomplete | Medium | ✅ Fixed |
| 8 | Permission hint logic | Medium | ✅ Fixed |
| 9 | Excessive NSLog usage | Medium | ✅ Fixed |
| 10 | Force cast crash risk | Medium | ✅ Fixed |
| 11 | Missing Sendable conformance | Medium | ✅ Fixed |
| 12 | File header mismatch | Low | ✅ Fixed |
| 13 | Dead code / debug artifacts | Low | ✅ Fixed |
| 14 | State duplication | Low | ✅ Fixed |
| 15 | Magic numbers | Low | ✅ Fixed |
| 16 | Inefficient array operations | Low | ✅ Fixed |
| 17 | Inconsistent preview patterns | Low | ✅ Fixed |
| 18 | Unused stored property | Low | ✅ Fixed |

---

## Critical Issues

### 1. Thread Safety in HID Service *(All reviewers)* ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift:15-23, 351, 881, 1166, 1341`

```swift
final class HIDFAPWaiter {
    var response: [UInt8]?
    var done: Bool = false
```

**Problems identified:**
- `HIDFAPWaiter` is accessed across threads (C callback + run loop) without synchronization
- Shared caches (`cachedDeviceIndex`, `cachedDPIFeatureIndex`, etc.) mutated while multiple tasks call into the service
- `settingsChangeSubject.send()` invoked off the main thread; Combine subjects are not thread-safe
- Callback uses `Unmanaged<HIDFAPWaiter>.fromOpaque()` which can crash if waiter is deallocated early

**Recommended fix:**

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

**Better approach:** Isolate all HID I/O behind an `actor` or serial executor:

```swift
actor HIDExecutor {
    func executeHIDOperation<T>(_ operation: () async throws -> T) async throws -> T {
        // Serialized HID access
    }
}
```

---

### 2. Mixed Threading Patterns *(All reviewers)* ✅ FIXED

**Location:** `Application/lsomApp.swift:218`

```swift
Thread.detachNewThread { [weak self] in
    // ...
    Task.detached {
        // ...
    }
    _ = semaphore.wait(timeout: .now() + 10)
}
```

**Problems identified:**
- Mixes `Thread.detachNewThread`, `Task.detached`, and `DispatchSemaphore`
- The detached task can run on a different thread than intended
- Timeout can cause stale data reads
- Cancellation is lost
- Semaphore inside async context is deprecated pattern

**Recommended fix:** Use structured concurrency:

```swift
func refreshAllData() async {
    async let battery = batteryService.batteryPercentage()
    async let dpi = mouseSettingsService.dpiSettings(forSensor: 0)
    async let polling = mouseSettingsService.pollingRateInfo()

    let (b, d, p) = await (try? battery, try? dpi, try? polling)
    // Update UI on MainActor
}
```

---

## High Priority Issues

### 3. God Class: LogitechHIDService ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift`

**Problem:** Single class handles 10+ responsibilities:
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
- Connection events

**Recommended split:**
- `HIDTransport` - low-level I/O
- `HIDPPCommandExecutor` - FAP/RAP protocol
- `UnifiedBatteryReader`
- `DPIController`
- `PollingRateController`
- `ButtonMappingController`

**Example structure:**

```swift
// Low-level transport protocol
protocol HIDTransport: Sendable {
    func sendFAPCommand(deviceIndex: UInt8, featureIndex: UInt8,
                        function: UInt8, params: [UInt8]) -> [UInt8]?
    func sendRAPCommand(deviceIndex: UInt8, subId: UInt8,
                        register: UInt8, params: [UInt8]) -> RAPResponse?
}

// Serialized command executor using Swift Concurrency
actor HIDPPCommandExecutor {
    private let transport: HIDTransport

    func execute<T: HIDPPResponse>(_ command: HIDPPCommand) async throws -> T {
        // All HID I/O serialized here
    }
}

// Focused feature readers
final class UnifiedBatteryReader: BatteryService {
    private let executor: HIDPPCommandExecutor

    func batteryPercentage() async throws -> Int {
        let response: BatteryResponse = try await executor.execute(.getBattery)
        return response.stateOfCharge
    }
}

final class DPIController {
    private let executor: HIDPPCommandExecutor

    func currentDPI(forSensor sensor: Int) async throws -> Int { ... }
    func setDPI(_ dpi: Int, forSensor sensor: Int) async throws { ... }
}
```

---

### 4. IOKit Import in Domain Layer ✅ FIXED

**Location:** `Domain/BatteryService.swift:10-11`

```swift
import IOKit
import IOKit.hid
```

**Problem:** Domain layer should contain only business logic. `IOKit` imports violate clean architecture dependency rules.

**Fix:** Remove IOKit imports; use `Int32` instead of `IOReturn`:

```swift
case deviceOpenFailed(code: Int32)
```

---

### 5. `unowned` Reference Risk ✅ FIXED

**Location:** `Presentation/PopoverViewModel.swift:17`, `Presentation/SettingsView.swift:17`

```swift
private unowned let appDelegate: AppDelegate
```

**Problem:** Crash risk if `AppDelegate` is deallocated before ViewModel.

**Fix:**

```swift
// Before:
private unowned let appDelegate: AppDelegate

// After (Option A - weak reference):
private weak var appDelegate: AppDelegate?

func refresh() {
    appDelegate?.refreshAllData()  // Safe optional access
}

// After (Option B - inject only what's needed):
@MainActor
final class PopoverViewModel: ObservableObject {
    private let refreshAction: () -> Void
    private let batteryPublisher: AnyPublisher<Int?, Never>
    private var cancellables = Set<AnyCancellable>()

    init(refreshAction: @escaping () -> Void,
         batteryPublisher: AnyPublisher<Int?, Never>) {
        self.refreshAction = refreshAction
        self.batteryPublisher = batteryPublisher

        batteryPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$batteryPercent)
    }

    func refresh() {
        refreshAction()  // No reference to AppDelegate needed
    }
}
```

---

### 6. Singleton Anti-pattern ✅ FIXED

**Location:** `Infrastructure/HIDLogService.swift:14`

```swift
static let shared = HIDLogService()
```

**Problem:** Singletons make testing difficult and hide dependencies.

**Fix:** Inject through `AppEnvironment`:

```swift
final class AppEnvironment {
    let logService: HIDLogService
}
```

---

## Medium Priority Issues

### 7. Preview Detection Incomplete *(2/3 reviewers)* ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift:105-108`

```swift
private static var isPreviewMode: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
}
```

**Problem:** SwiftUI Previews set `XCODE_RUNNING_FOR_PREVIEWS`, not `XCODE_RUNNING_FOR_PLAYGROUNDS`. Previews can still hit IOKit and crash.

**Fix:**

```swift
private static var isPreviewMode: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
}
```

---

### 8. Permission Hint Logic Flawed *(2/3 reviewers)* ✅ FIXED

**Location:** `Presentation/PopoverView.swift:51-67`

**Problem:** Treats `batteryPercent == nil` as "permission denied," conflating:
- Unsupported features
- Transient errors
- Device disconnection

**Fix:** Use `LogitechHIDError.isPermissionsRelated` plus connection state:

```swift
showPermissionHint = !hasDismissedHint
    && !isReceiverConnected
    && lastError?.isPermissionsRelated == true
```

---

### 9. Excessive NSLog/print Usage *(All reviewers)* ✅ FIXED

**Locations:** `Infrastructure/LogitechHIDService.swift:1171, 2024`, `Presentation/SettingsView.swift:146-167`

```swift
NSLog("POLLING: [UI] applyPollingRate called - new=%d, previous=%d", rate, previousRate)
```

**Problems:**
- 50+ `NSLog` calls in release builds
- Leaks device info
- Adds overhead
- Inconsistent with custom `HIDLogService`

**Fix:** Use OSLog with privacy annotations:

```swift
import os.log

private let logger = Logger(subsystem: "com.lsom", category: "HID")
logger.debug("Polling rate: \(rate, privacy: .public)")
```

---

### 10. Force Cast Crash Risk *(2/3 reviewers)* ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift:2470`

```swift
if CFNumberGetValue((value as! CFNumber), .sInt32Type, &int32) {
```

**Fix:**

```swift
if let cfNumber = value as? CFNumber {
    CFNumberGetValue(cfNumber, .sInt32Type, &int32)
}
```

---

### 11. Missing Sendable Conformance ✅ FIXED

**Locations:** `Domain/BatteryService.swift`, `Domain/MouseSettingsService.swift`

**Problem:** Model types are `Sendable` but protocols are not.

**Fix:**

```swift
protocol BatteryService: Sendable {
    func batteryPercentage() throws -> Int
}
```

---

### 12. File Header Mismatch ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift:1-6`

```swift
//  HIDDebugService.swift  // <-- Wrong filename
```

**Fix:**

```swift
// Before:
//
//  HIDDebugService.swift
//  lsom
//
//  Created by ...

// After:
//
//  LogitechHIDService.swift
//  lsom
//
//  Core HID++ 2.0 FAP/RAP implementation for Logitech devices.
//
```

---

## Low Priority Issues

### 13. Dead Code / Debug Artifacts *(All reviewers)* ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift:812-818`

```swift
// M O
// 6 6
// 7 2
// 5 7
// 8 3
```

Also: Disabled `hidLog()` function with commented-out code.

**Fix:**

```swift
// 1. Delete the stray debug comment block entirely (lines 812-818)

// 2. For the disabled hidLog function, either remove it or re-enable with DEBUG gate:

// Option A - Remove entirely if not needed

// Option B - Re-enable with proper DEBUG gating:
#if DEBUG
private let hidLogTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private func hidLog(_ message: @autoclosure () -> String) {
    let msg = message()
    let timestamp = hidLogTimestampFormatter.string(from: Date())
    print("[\(timestamp)] HID: \(msg)")
}
#else
@inline(__always)
private func hidLog(_ message: @autoclosure () -> String) { }
#endif
```

---

### 14. State Duplication *(All reviewers)* ✅ FIXED

**Locations:** `Application/lsomApp.swift:256`, `Presentation/SettingsView.swift:57`

**Problem:** `showPercentage` default set in multiple places.

**Fix:** Use `@AppStorage`:

```swift
@AppStorage(UserDefaultsKey.showPercentageInMenuBar) var showPercentage = true
```

---

### 15. Magic Numbers ✅ FIXED

**Location:** `Infrastructure/LogitechHIDService.swift:450, 667`

```swift
let timeout: TimeInterval = 0.5
let candidateIndexes: [UInt8] = [1, 2, 3, 4, 5, 6]
```

**Fix:** Centralize in `HIDPP` enum:

```swift
private enum HIDPP {
    static let defaultTimeout: TimeInterval = 0.5
    static let deviceIndexRange: ClosedRange<UInt8> = 1...6
}
```

---

### 16. Inefficient Array Operations ✅ FIXED

**Location:** `Domain/HIDPPParsing.swift:183`

```swift
let unique = Array(Set(values)).sorted()
```

**Problem:** O(n) Set creation + O(n log n) sort. Also loses original order before sorting.

**Fix:**

```swift
// Option A - Using Swift Collections package (recommended for frequent use):
import OrderedCollections

let unique = Array(OrderedSet(values))  // Preserves first occurrence order, O(n)

// Option B - Inline deduplication (no external dependency):
var seen = Set<Int>()
let unique = values.filter { seen.insert($0).inserted }  // O(n), preserves order

// Option C - If sorted output is actually needed:
let unique = values.reduce(into: [Int]()) { result, value in
    if !result.contains(value) {
        result.append(value)
    }
}.sorted()  // O(n²) contains check, but often fine for small arrays
```

---

### 17. Inconsistent Preview Patterns ✅ FIXED

**Location:** `Presentation/PopoverView.swift:444-518`

**Problem:** `PopoverPreviewContainer` duplicates view hierarchy.

**Fix:** Create mock ViewModel:

```swift
#if DEBUG
extension PopoverViewModel {
    static func preview(batteryPercent: Int? = 89) -> PopoverViewModel { ... }
}
#endif
```

---

### 18. Unused Stored Property ✅ FIXED

**Location:** `Presentation/PopoverView.swift:15-17`

```swift
private let hidService: LogitechHIDService  // Never used
```

**Fix:**

```swift
// Before:
@MainActor
final class PopoverViewModel: ObservableObject {
    private let hidService: LogitechHIDService
    private let permissionsService: PermissionsService
    private unowned let appDelegate: AppDelegate

    init(
        appDelegate: AppDelegate,
        hidService: LogitechHIDService,
        permissionsService: PermissionsService
    ) {
        self.appDelegate = appDelegate
        self.hidService = hidService  // Stored but never used
        self.permissionsService = permissionsService
        // ...
    }
}

// After:
@MainActor
final class PopoverViewModel: ObservableObject {
    private let permissionsService: PermissionsService
    private unowned let appDelegate: AppDelegate

    init(
        appDelegate: AppDelegate,
        permissionsService: PermissionsService
    ) {
        self.appDelegate = appDelegate
        self.permissionsService = permissionsService
        // ...
    }
}

// Also update call site in lsomApp.swift:
PopoverViewModel(
    appDelegate: self,
    permissionsService: env.permissionsService
)
```

---

## Modern Swift Recommendations

### Swift 5.9+ / macOS 14+

| Current | Modern |
|---------|--------|
| `@Published` + `ObservableObject` | `@Observable` + `@Bindable` |
| `UserDefaults.standard.bool(forKey:)` | `@AppStorage("key")` |
| Manual timers | `Clock` / `sleep(for:)` |
| Combine subjects | `AsyncStream` |
| Ternary conditionals | `if`/`switch` expressions |

### Swift 6 Preparation

```swift
// Current:
func batteryPercentage() throws -> Int

// Swift 6:
func batteryPercentage() throws(LogitechHIDError) -> Int
```

---

## Prioritized Action Items

### Immediate (Before Next Release)
1. Fix thread safety in `HIDFAPWaiter` with `NSLock`
2. Add `XCODE_RUNNING_FOR_PREVIEWS` check
3. Remove dead debug comments
4. Fix file header mismatch

### Short-term
1. Remove IOKit imports from Domain layer
2. Replace `unowned` with `weak` or DI
3. Consolidate logging to OSLog
4. Fix permission hint logic

### Medium-term
1. Split `LogitechHIDService` into focused components
2. Introduce HID `actor` for serialized access
3. Inject `HIDLogService` instead of singleton
4. Add unit tests for `HIDPPParsing`

### Long-term
1. Adopt `@Observable` when targeting macOS 14+
2. Replace Combine with `AsyncStream`
3. Prepare for Swift 6 typed throws
4. Use `Clock` for timer operations

---

## Files Reviewed

| File | Lines | Key Issues |
|------|-------|------------|
| `Infrastructure/LogitechHIDService.swift` | ~2,487 | Thread safety, god class |
| `Presentation/SettingsView.swift` | ~1,060 | NSLog, state duplication |
| `Presentation/PopoverView.swift` | ~519 | Permission logic, unused property |
| `Application/lsomApp.swift` | ~299 | Mixed threading |
| `Domain/HIDPPParsing.swift` | ~413 | Inefficient array ops |
| `Domain/MouseDeviceState.swift` | ~173 | Clean |
| `Domain/MouseSettingsService.swift` | ~141 | Missing Sendable |
| `Infrastructure/HIDLogService.swift` | ~166 | Singleton |
| `Domain/BatteryService.swift` | ~83 | IOKit import |
| `Infrastructure/SystemPermissionsService.swift` | ~55 | Clean |
| `Application/AppEnvironment.swift` | ~43 | Clean |
| `Domain/PermissionsServices.swift` | ~29 | Clean |
| `Application/AutoRefreshInterval.swift` | ~28 | Clean |

---

## Appendix: Source Reviews

This report consolidates findings from:

1. **CODE_REVIEW-OPUS_4_5.md** - Claude Opus 4.5 (477 lines, 21 detailed issues with code examples)
2. **CODE_REVIEW-GPT_5_2_CODEX_XHIGH.md** - GPT 5.2 Codex (32 lines, focused on concurrency)
3. **CODE_REVIEW-GPT_5_1_CODEX_MAX_XHIGH.md** - GPT 5.1 Codex Max (43 lines, similar to GPT 5.2)

All original review files are preserved in the repository for reference.
