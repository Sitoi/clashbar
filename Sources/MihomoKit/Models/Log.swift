import Foundation

public struct LogsResponse: Decodable, Equatable, Sendable {
    public let logs: [LogLine]?

    public init(logs: [LogLine]?) {
        self.logs = logs
    }
}

public struct LogLine: Decodable, Equatable, Sendable {
    public let type: String?
    public let payload: String?

    public init(type: String?, payload: String?) {
        self.type = type
        self.payload = payload
    }
}
