# HID++ 2.0 Implementation Analysis

**Project:** lsom (Logitech Status on Mac)
**Analysis Date:** January 2026
**Key Files Analyzed:**
- `lsom/Infrastructure/LogitechHIDService.swift` (~1,800 lines)
- `lsom/Domain/HIDPPParsing.swift` (~220 lines)

---

## Executive Summary

The **lsom** macOS application implements a sophisticated HID++ 2.0 FAP (Feature Access Protocol) client for communicating with Logitech Unifying Receivers. The implementation demonstrates **strong protocol compliance**, **robust error handling**, and **careful memory safety practices**.

| Aspect | Rating | Notes |
|--------|--------|-------|
| Protocol Compliance | Excellent | Strictly HID++ 2.0 FAP spec; supports legacy RAP |
| Report Structure | Excellent | Correct 20-byte format, proper encoding |
| Feature Discovery | Excellent | Dynamic via Root.GetFeature, caching |
| Error Handling | Very Good | Comprehensive error types |
| Memory Safety | Excellent | Careful pointer management, immediate cleanup |
| Concurrency | Very Good | NSLock protection, run-loop integration |
| Threading | Good | Callback-driven, run-loop dependent |

---

## 1. Protocol Compliance

### HID++ 2.0 FAP Specification Adherence

The implementation **strictly follows the HID++ 2.0 FAP specification**:

**Report Structure (20-byte long reports, Report ID 0x11):**
```
tx[0] = 0x11                           // Long report ID
tx[1] = deviceIndex                    // Device index (1-6 for paired devices, 0xFF for receiver)
tx[2] = featureIndex                   // Feature index (0x00 = Root)
tx[3] = (functionIndex << 4) | softwareId  // Function/Software ID byte
tx[4..19] = params                     // 16 parameter bytes
```

**Compliance Checklist:**
- ✅ **Software ID:** Hardcoded to `0x01`, per HID++ 2.0 specification
- ✅ **Function Index Encoding:** 4-bit function index in high nibble, 4-bit client ID in low nibble
- ✅ **Timeout Handling:** 2-second timeout matches hidapi behavior
- ✅ **Device Index Range:** Correctly probes indices 1-6 for paired devices
- ✅ **Feature Discovery:** Root.GetFeature (0x0000) for dynamic feature index lookup
- ✅ **Error Detection:** Feature Index 0xFF reserved for error responses

**Legacy Support (HID++ 1.0 RAP):**
The code maintains backward compatibility with HID++ 1.0 Register Access Protocol (RAP) using short 7-byte reports (Report ID 0x10) for devices that don't support HID++ 2.0.

---

## 2. Report Structure Analysis

### FAP Long Report (0x11, 20 bytes total)

| Offset | Field | Purpose |
|--------|-------|---------|
| 0 | 0x11 | Report ID (identifies as HID++ long report) |
| 1 | Device Index | Target device (1-6) or 0xFF for receiver |
| 2 | Feature Index | Feature index (0x00 = Root/Error) |
| 3 | Func/SoftID | [func:4 bits \| softID:4 bits] |
| 4-19 | Parameters | Up to 16 bytes of command data |

**Response Mirroring:** Responses mirror the request structure (bytes 0-3), with params populated according to the function specification.

### RAP Short Report (0x10, 7 bytes total)

| Offset | Field | Purpose |
|--------|-------|---------|
| 0 | 0x10 | Report ID (HID++ 1.0 short report) |
| 1 | Device Index | Target device |
| 2 | SubID | GET_REGISTER (0x81) or SET_REGISTER (0x80) |
| 3 | Register | Register index (e.g., 0x07 = battery status) |
| 4-6 | Parameters | Register data or response |

Error detection: SubID 0x8F indicates error response, with error code in params[0].

---

## 3. Feature Discovery Mechanism

### Root.GetFeature (Feature 0x0000)

The implementation uses **dynamic feature discovery** via Root.GetFeature:

```swift
func rootGetFeatureIndexFAP(
    device: IOHIDDevice,
    deviceIndex: UInt8,
    featureId: UInt16
) -> (featureIndex: UInt8, featureType: UInt8)?
```

**Key Behaviors:**
- ✅ **Feature Index 0 = Not Found:** Correctly interprets index 0 as "feature not supported"
- ✅ **Caching:** Results cached per device to avoid repeated queries
- ✅ **Type Discovery:** Returns both feature index AND feature type byte
- ✅ **Device Enumeration:** Probes device indices 1-6 sequentially until finding active device

**Supported Features (by ID):**

| Feature ID | Name | Purpose |
|------------|------|---------|
| 0x0001 | IFeatureSet | Feature enumeration |
| 0x0005 | Device Name | Device identification |
| 0x1004 | Unified Battery | Battery status (HID++ 2.0) |
| 0x2201 | Adjustable DPI | DPI configuration |
| 0x8060 | Report Rate | Standard polling rate |
| 0x8061 | Extended Report Rate | High-speed polling (>1000Hz) |
| 0x1B04 | Special Keys & Mouse Buttons | Button mapping |
| 0x8100 | Onboard Profiles | Device profiles |

---

## 4. Device Communication Flow

### Connection Initialization

```
1. IOHIDManagerCreate()
   ├─ Set device matching filter (VID=0x046D, PID=0xC547)
   ├─ Register device matching callback
   ├─ Register device removal callback
   └─ Schedule on main run loop

2. IOHIDManagerOpen()
   └─ Opens HID subsystem

3. Device Discovered
   ├─ Callback triggered for HID++ interface (usagePage 0xFF00)
   └─ deviceConnectionSubject.send(true)

4. ensureReceiverOpen()
   ├─ Check if already open (cache hit)
   └─ Scan devices via IOHIDManagerCopyDevices()
       ├─ Filter: VID=0x046D, PID=0xC547
       ├─ Filter: usagePage=0xFF00 (HID++)
       ├─ IOHIDDeviceOpen() [requires Input Monitoring permission]
       └─ Cache IOHIDDevice reference
```

### Command Execution Pipeline

```
User calls batteryPercentage()
    ↓
ensureReceiverOpen()
    ↓
findActiveDeviceIndex() [probes indices 1-6]
    ├─ Root.GetFeature(0x0001) for each index
    └─ Returns first responding device
    ↓
getFeatureIndex(featureId: 0x1004) [Unified Battery]
    ├─ Root.GetFeature(0x1004)
    └─ Caches result
    ↓
sendFAPCommandInternal()
    ├─ Build 20-byte report
    ├─ Register input report callback
    ├─ IOHIDDeviceSetReport() [send]
    ├─ Pump run loop until response
    └─ IOHIDDeviceGetReport() or callback receipt
    ↓
HIDPPParsing.parseUnifiedBatteryStatus(response)
    └─ Extract state_of_charge from response[4]
```

---

## 5. Error Handling & Resilience

### Error Detection Mechanisms

**1. HID++ Protocol Errors**

Feature index 0xFF indicates error response:
```swift
func fapErrorCode(from response: [UInt8]) -> UInt8? {
    guard response.count >= 6 else { return nil }
    guard response[0] == 0x11 else { return nil }
    guard response[2] == 0xFF else { return nil }  // Error marker
    return response[5]  // Error code
}
```

**Standard HID++ Error Codes:**

| Code | Name | Meaning |
|------|------|---------|
| 0x01 | UNKNOWN | Unsupported function |
| 0x02 | INVALID_ARGUMENT | Bad parameter |
| 0x03 | OUT_OF_RANGE | Value out of range |
| 0x04 | HARDWARE_ERROR | Device hardware error |
| 0x05 | NOT_ALLOWED | Permission denied by device |
| 0x06 | INVALID_FEATURE_INDEX | Bad feature index |
| 0x07 | INVALID_FUNCTION | Bad function ID |
| 0x08 | BUSY | Device busy |

**2. IOKit Error Handling**

```swift
let openDeviceResult = IOHIDDeviceOpen(found, IOOptionBits(kIOHIDOptionsTypeNone))
guard openDeviceResult == kIOReturnSuccess else {
    if openDeviceResult == kIOReturnNotPrivileged {
        throw LogitechHIDError.permissionDenied  // Input Monitoring not granted
    } else {
        throw LogitechHIDError.deviceOpenFailed(code: Int32(openDeviceResult))
    }
}
```

**3. Timeout Handling**

- 500ms timeout per HIDPPConstants
- 50ms pump intervals
- Returns nil on timeout, propagates as `unexpectedResponse`

### Error Types (LogitechHIDError)

```swift
enum LogitechHIDError: Error {
    case receiverNotFound              // No Logitech receiver found
    case permissionDenied              // Input Monitoring not granted
    case deviceOpenFailed(code: Int32) // IOReturn error code
    case featureNotFound(featureId: UInt16)  // Feature not supported
    case unexpectedResponse            // Response parsing failed
    case settingRejected(errorCode: UInt8)  // Device rejected command
}
```

### Resilience Patterns

**Feature Fallback (Polling Rate):**
```swift
// Try standard feature (0x8060) first
if hasStandard { /* try standard */ }

// Fall back to extended feature (0x8061)
if hasExtended { /* try extended */ }

// Verify write succeeded by reading back
if await verifyApplied() { /* success */ }
```

**Multi-index Probing:**
```swift
let candidateIndexes = Array(HIDPPConstants.deviceIndexRange)  // 1...6
for dIdx in candidateIndexes {
    if let result = try? fetchFor(dIdx) {
        return result
    }
}
throw lastError  // All indices failed
```

---

## 6. Threading & Concurrency

### Concurrency Model

**1. NSLock-Protected State (HIDFAPWaiter)**

```swift
final class HIDFAPWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var _response: [UInt8]?
    private var _done: Bool = false
}
```

**Rationale:** Accessed from both C callback (arbitrary thread) and run-loop polling thread.

**2. C Callback Synchronization**

```swift
private let hidFAPInputCallback: IOHIDReportCallback = {
    (context, result, sender, type, reportID, report, reportLength) in
    guard result == kIOReturnSuccess, let context = context else { return }

    let waiter = Unmanaged<HIDFAPWaiter>.fromOpaque(context)
        .takeUnretainedValue()

    // Guard reportID to avoid capturing unrelated reports
    guard reportID == waiter.reportID else { return }

    // Thread-safe write
    waiter.response = Array(...)
    waiter.done = true
}
```

**3. Run Loop Management**

- Callback registered before send
- Run loop pumped until response or timeout
- Callback unregistered before waiter cleanup (critical for memory safety)

**4. Actor Isolation**

```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // UI updates always on main thread
}
```

### Thread Constraints

| Operation | Thread Requirement |
|-----------|-------------------|
| Input Report Callback | Any (IOKit thread) |
| FAP Send | Thread with active run loop |
| UI Updates | MainActor |
| Device Search | Any (typically main) |

---

## 7. Memory Safety & Callback Management

### Pointer Management

**C Callback Context Bridge:**

```swift
// Create waiter and bridge to opaque context
let waiter = HIDFAPWaiter(reportID: UInt32(HIDPPConstants.longReportId))
let context = UnsafeMutableRawPointer(
    Unmanaged.passUnretained(waiter).toOpaque()
)

// Register callback with context
IOHIDDeviceRegisterInputReportCallback(device, &cbBuffer, cbBuffer.count,
                                       hidFAPInputCallback, context)

// CRITICAL: Unregister before waiter goes out of scope
IOHIDDeviceRegisterInputReportCallback(device, &cbBuffer, cbBuffer.count,
                                       nil, nil)
```

**Safety Analysis:**
- ✅ `takeUnretainedValue()` is correct (waiter is on stack, callback scope-limited)
- ✅ Callback is unregistered before waiter deinit
- ⚠️ If waiter left registered beyond scope → **dangling pointer** (would crash)

**UnsafeBufferPointer Conversion:**

```swift
let bytes: [UInt8]
if reportLength > 0 {
    let buf = UnsafeBufferPointer(start: report, count: Int(reportLength))
    bytes = Array(buf)  // Copy to safe Swift array
} else {
    bytes = []
}
```

**Safety:** Creates temporary UnsafeBufferPointer, immediately copied to Array.

### Object Lifecycle

```
HIDFAPWaiter (stack-allocated)
    ↓
Unmanaged.passUnretained() → opaque context
    ↓ [passed to C callback]
C callback thread:
    Unmanaged.fromOpaque().takeUnretainedValue()
    (no retain/release, just reads reference)
    ↓
Wait for callback to complete or timeout
    ↓
Unregister callback before waiter deinit
    ↓
Waiter goes out of scope safely
```

---

## 8. Protocol Examples

### Battery Reading (Feature 0x1004)

```
REQUEST (20 bytes):
[0]    = 0x11              # Long report ID
[1]    = 0x01              # Device index 1
[2]    = featureIndex      # Discovered index for 0x1004
[3]    = 0x01              # Function 0x00, Software ID 1
[4-19] = 0x00              # No parameters

RESPONSE:
[4]    = 0x42              # State of charge (66%)
```

### DPI Reading (Feature 0x2201)

```
STEP 1: Discover feature index
REQUEST: Root.GetFeature(0x2201)
RESPONSE: [4] = featureIndex

STEP 2: Get sensor count
REQUEST: [2] = featureIndex, [3] = 0x00
RESPONSE: [4] = sensorCount

STEP 3: Get supported DPI list
REQUEST: [2] = featureIndex, [3] = 0x01, [4] = sensorIndex
RESPONSE: [4..19] = DPI values (big-endian uint16)

STEP 4: Get current DPI
REQUEST: [2] = featureIndex, [3] = 0x02, [4] = sensorIndex
RESPONSE: [4..5] = currentDPI, [6..7] = defaultDPI
```

### Polling Rate (Feature 0x8060 vs 0x8061)

**Standard (0x8060):**
- Supported rates: bitmask where bit N = rate index N
- Current rate: interval in milliseconds

**Extended (0x8061):**
- Supported rates: bitmask (bit 0=125Hz, 1=250Hz, 2=500Hz, 3=1000Hz, 4=2000Hz, 5=4000Hz, 6=8000Hz)
- Set rate: pass index value (0-6)

---

## 9. Strengths

1. **Spec-Compliant:** Strictly follows HID++ 2.0 FAP protocol
2. **Memory Safe:** Careful pointer management, immediate cleanup of callbacks
3. **Resilient:** Multi-index probing, feature fallbacks, error recovery
4. **Well-Documented:** Comprehensive logging, parsing helpers are unit-testable
5. **Concurrency-Aware:** NSLock protection, run-loop integration, @MainActor isolation

---

## 10. Known Limitations

1. **Single Device Support:** Only supports one paired device at a time
2. **Unifying Receiver Only:** PID 0xC547 only; doesn't support other Logitech USB receivers
3. **Preview Mode:** Full HID initialization skipped in Xcode Previews
4. **No Async Request Queueing:** FAP commands are synchronous
5. **Run Loop Dependency:** FAP must be called from thread with active run loop

---

## 11. Edge Cases Handled

- ✅ Feature not supported → 0 returned by Root.GetFeature
- ✅ Device disconnection → Callback clears receiver, publishes event
- ✅ Permission denial → `kIOReturnNotPrivileged` → distinct error type
- ✅ Timeout → Returns nil, propagates as `unexpectedResponse`
- ✅ Malformed response → Length checks, parsing validators
- ✅ Legacy HID++ 1.0 → RAP protocol implemented for older devices

---

## 12. Recommendations for Future Enhancement

1. **Async Request Batching:** Queue multiple FAP commands to reduce latency
2. **Multi-Device Support:** Track multiple device indices, return aggregated state
3. **Receiver Enumeration:** Support additional Logitech receivers (different PIDs)
4. **Response Caching:** Cache feature indices and device capabilities longer
5. **Unit Tests:** `HIDPPParsing` is test-ready; expand coverage
6. **Custom Icon:** Replace `computermouse` SF Symbol with app-specific menu bar icon

---

## Conclusion

This implementation represents a **production-grade HID++ 2.0 client** suitable for reliable low-level hardware communication with Logitech input devices on macOS. The codebase demonstrates excellent understanding of the HID++ protocol, careful memory management for C interop, and robust error handling patterns.
