import AppKit
import Foundation
import MihomoKit

enum StatusBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly = "icon_only"
    case iconAndSpeed = "icon_and_speed"
    case speedOnly = "speed_only"

    var id: String {
        rawValue
    }
}

struct MenuBarSpeedLines: Equatable {
    let up: String
    let down: String

    static let zero = MenuBarSpeedLines(up: "0K↑", down: "0K↓")
}

struct MenuBarDisplay: Equatable {
    let mode: StatusBarDisplayMode
    let symbolName: String?
    let speedLines: MenuBarSpeedLines?
    let isRunning: Bool
    let isTunEnabled: Bool
}

struct StatusItemBanner: Equatable, Identifiable {
    let id = UUID()
    let symbolName: String
    let title: String
    let primaryDetail: String
    let secondaryDetail: String?
}

enum MenuBarDisplayBuilder {
    static func resolveVisualStatus(
        statusText: String,
        isProcessRunning: Bool,
        apiStatus: APIHealth) -> RuntimeVisualStatus
    {
        let normalized = statusText.lowercased()
        if normalized == "starting" {
            return .starting
        }
        if normalized == "failed" {
            return .failed
        }
        guard isProcessRunning || normalized == "running" else { return .stopped }
        switch apiStatus {
        case .healthy: return .runningHealthy
        case .failed: return .failed
        case .degraded, .unknown: return .runningDegraded
        }
    }

    static func symbolName(for visualStatus: RuntimeVisualStatus) -> String {
        switch visualStatus {
        case .runningHealthy: "bolt.horizontal.circle.fill"
        case .runningDegraded: "bolt.horizontal.circle"
        case .starting: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .stopped: "bolt.slash.circle"
        }
    }

    static func compactMenuBarRate(_ bytesPerSecond: Int64) -> String {
        let normalizedBytes = max(0, bytesPerSecond)
        guard normalizedBytes > 0 else { return "0K" }
        var value = Double(normalizedBytes) / 1024
        let units = ["K", "M", "G", "T"]
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let format = value < 10 ? "%.2f%@" : (value < 100 ? "%.1f%@" : "%.0f%@")
        return String(format: format, min(value, 999), units[unitIndex])
    }

    static func speedLines(up: Int64, down: Int64, isRunning: Bool) -> MenuBarSpeedLines {
        guard isRunning else { return .zero }
        let upStr = self.compactMenuBarRate(max(0, up))
        let downStr = self.compactMenuBarRate(max(0, down))
        return MenuBarSpeedLines(up: "\(upStr)↑", down: "\(downStr)↓")
    }

    static func build(
        mode: StatusBarDisplayMode,
        visualStatus: RuntimeVisualStatus,
        isRunning: Bool,
        traffic: (up: Int64, down: Int64),
        isTunEnabled: Bool) -> MenuBarDisplay
    {
        MenuBarDisplay(
            mode: mode,
            symbolName: mode == .speedOnly ? nil : self.symbolName(for: visualStatus),
            speedLines: mode == .iconOnly ? nil : self.speedLines(
                up: traffic.up,
                down: traffic.down,
                isRunning: isRunning),
            isRunning: isRunning,
            isTunEnabled: isTunEnabled)
    }
}
