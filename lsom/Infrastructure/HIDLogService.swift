//
//  HIDLogService.swift
//  lsom
//
//  Persistent logging service for HID++ protocol traffic.
//  Logs are written to a hidden file in the user's Application Support directory.
//

import Foundation

/// Service for logging HID++ protocol traffic to a persistent file.
final class HIDLogService {
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.lsom.hidlog", qos: .utility)
    private let timestampFormatter: ISO8601DateFormatter

    init() {
        timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Create log directory in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let logDir = appSupport.appendingPathComponent("lsom", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: logDir,
                withIntermediateDirectories: true
            )
        } catch {
            print("lsom: Failed to create log directory: \(error)")
        }

        // Log file with date in name, hidden with dot prefix
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logDir.appendingPathComponent(".hidpp-\(dateString).log")

        // Create or open file for appending
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            handle.seekToEndOfFile()
            fileHandle = handle
        } catch {
            print("lsom: Failed to open log file: \(error)")
            fileHandle = nil
        }

        // Write session header
        log("=== lsom HID++ Log Session Started ===")
        log("Log file: \(logFileURL.path)")
    }

    deinit {
        try? fileHandle?.close()
    }

    /// Log a message with timestamp.
    func log(_ message: String) {
        queue.async { [weak self] in
            guard let self, let handle = self.fileHandle else { return }

            let timestamp = self.timestampFormatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"

            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    /// Log HID++ FAP transmit data.
    func logFAPTransmit(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionByte: UInt8,
        params: [UInt8]
    ) {
        let paramsHex = params.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        log("FAP TX: devIdx=0x\(String(format: "%02X", deviceIndex)) featIdx=0x\(String(format: "%02X", featureIndex)) func=0x\(String(format: "%02X", functionByte)) params=[\(paramsHex)]")
    }

    /// Log HID++ FAP receive data.
    func logFAPReceive(bytes: [UInt8]) {
        let bytesHex = bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        log("FAP RX: [\(bytesHex)]")
    }

    /// Log HID++ RAP transmit data.
    func logRAPTransmit(
        deviceIndex: UInt8,
        subId: UInt8,
        register: UInt8,
        params: [UInt8]
    ) {
        let paramsHex = params.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        log("RAP TX: devIdx=0x\(String(format: "%02X", deviceIndex)) subId=0x\(String(format: "%02X", subId)) reg=0x\(String(format: "%02X", register)) params=[\(paramsHex)]")
    }

    /// Log HID++ RAP receive data.
    func logRAPReceive(bytes: [UInt8]) {
        let bytesHex = bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        log("RAP RX: [\(bytesHex)]")
    }

    /// Log device connection event.
    func logDeviceConnected(vendorId: Int, productId: Int, usagePage: Int) {
        log("DEVICE CONNECTED: VID=0x\(String(format: "%04X", vendorId)) PID=0x\(String(format: "%04X", productId)) UsagePage=0x\(String(format: "%04X", usagePage))")
    }

    /// Log device disconnection event.
    func logDeviceDisconnected() {
        log("DEVICE DISCONNECTED")
    }

    /// Log a mouse device state snapshot.
    func logDeviceState(_ state: MouseDeviceState) {
        log(state.diagnosticDescription)
    }

    /// Log an error.
    func logError(_ message: String, error: Error? = nil) {
        if let error {
            log("ERROR: \(message) - \(error)")
        } else {
            log("ERROR: \(message)")
        }
    }

    /// Returns the path to the current log file.
    var currentLogFilePath: String {
        logFileURL.path
    }

    /// Returns all log file URLs in the log directory.
    func allLogFiles() -> [URL] {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let logDir = appSupport.appendingPathComponent("lsom", isDirectory: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: []
        ) else {
            return []
        }

        return contents
            .filter { $0.lastPathComponent.hasPrefix(".hidpp-") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
