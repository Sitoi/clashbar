import Foundation

public enum APIHealth: String, Sendable {
    case unknown
    case healthy
    case degraded
    case failed
}

public enum CoreMode: String, Codable, Sendable {
    case rule
    case global
    case direct
}

public struct VersionInfo: Decodable, Equatable, Sendable {
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

public struct VersionResponse: Decodable, Equatable, Sendable {
    public let version: String?

    public init(version: String?) {
        self.version = version
    }
}

public struct CoreUpgradeResponse: Decodable, Equatable, Sendable {
    public let status: String?
    public let message: String?

    public init(status: String?, message: String?) {
        self.status = status
        self.message = message
    }
}

public struct TrafficSnapshot: Decodable, Equatable, Sendable {
    public let up: Int64
    public let down: Int64
    public let upTotal: Int64?
    public let downTotal: Int64?

    private enum CodingKeys: String, CodingKey {
        case up
        case down
        case upTotal
        case downTotal
        case upTotalLower = "uptotal"
        case downTotalLower = "downtotal"
        case uploadTotal
        case downloadTotal
    }

    public init(up: Int64, down: Int64, upTotal: Int64? = nil, downTotal: Int64? = nil) {
        self.up = up
        self.down = down
        self.upTotal = upTotal
        self.downTotal = downTotal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.up = try container.decodeIfPresent(Int64.self, forKey: .up) ?? 0
        self.down = try container.decodeIfPresent(Int64.self, forKey: .down) ?? 0
        self.upTotal = try container.decodeIfPresent(Int64.self, forKey: .upTotal)
            ?? container.decodeIfPresent(Int64.self, forKey: .upTotalLower)
            ?? container.decodeIfPresent(Int64.self, forKey: .uploadTotal)
        self.downTotal = try container.decodeIfPresent(Int64.self, forKey: .downTotal)
            ?? container.decodeIfPresent(Int64.self, forKey: .downTotalLower)
            ?? container.decodeIfPresent(Int64.self, forKey: .downloadTotal)
    }
}

public struct MemorySnapshot: Decodable, Equatable, Sendable {
    public let inuse: Int64

    private enum CodingKeys: String, CodingKey {
        case inuse
    }

    public init(inuse: Int64) {
        self.inuse = inuse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inuse = try container.decodeIfPresent(Int64.self, forKey: .inuse) ?? 0
    }
}
