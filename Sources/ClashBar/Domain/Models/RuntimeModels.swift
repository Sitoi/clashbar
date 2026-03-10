import Foundation

enum APIHealth: String, Codable {
    case unknown
    case healthy
    case degraded
    case failed
}

enum CoreMode: String, Codable {
    case rule
    case global
    case direct
}

struct VersionInfo: Codable, Equatable {
    let version: String
}

struct CoreUpgradeResponse: Decodable, Equatable {
    let status: String?
    let message: String?
}

struct TrafficSnapshot: Decodable, Equatable {
    let up: Int64
    let down: Int64
    let upTotal: Int64?
    let downTotal: Int64?

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

    init(up: Int64, down: Int64, upTotal: Int64? = nil, downTotal: Int64? = nil) {
        self.up = up
        self.down = down
        self.upTotal = upTotal
        self.downTotal = downTotal
    }

    init(from decoder: Decoder) throws {
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

struct MemorySnapshot: Codable, Equatable {
    let inuse: Int64

    private enum CodingKeys: String, CodingKey {
        case inuse
    }

    init(inuse: Int64) {
        self.inuse = inuse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inuse = try container.decodeIfPresent(Int64.self, forKey: .inuse) ?? 0
    }
}
