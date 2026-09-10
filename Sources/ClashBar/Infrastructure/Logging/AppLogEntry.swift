import Foundation

enum AppLogSource: String, Equatable, CaseIterable, Identifiable {
    case clashbar
    case mihomo

    var id: String {
        rawValue
    }
}

struct AppErrorLogEntry: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: AppLogSource
    let level: String
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: AppLogSource = .clashbar,
        level: String,
        message: String)
    {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.message = message
    }

    func matches(keyword: String) -> Bool {
        self.message.localizedStandardContains(keyword)
            || self.level.localizedStandardContains(keyword)
            || self.source.rawValue.localizedStandardContains(keyword)
    }
}
