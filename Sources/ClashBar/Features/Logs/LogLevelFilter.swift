import Foundation

enum LogLevelFilter: Hashable, CaseIterable {
    case info
    case warning
    case error

    var titleKey: String {
        switch self {
        case .info: "ui.log_filter.info"
        case .warning: "ui.log_filter.warning"
        case .error: "ui.log_filter.error"
        }
    }

    static func from(_ level: String) -> LogLevelFilter {
        switch level.lowercased() {
        case "error": .error
        case "warning", "warn": .warning
        default: .info
        }
    }
}
