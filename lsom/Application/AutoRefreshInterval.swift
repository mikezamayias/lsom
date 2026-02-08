//
//  AutoRefreshInterval.swift
//  lsom
//
//  Simple enumeration for menu‑bar battery
//  auto‑refresh behaviour.
//

import Foundation

enum AutoRefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .oneMinute: return "Every 1 min"
        case .fiveMinutes: return "Every 5 min"
        case .fifteenMinutes: return "Every 15 min"
        }
    }
}

