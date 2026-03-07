import Foundation

struct ProxyGroupsResponse: Decodable, Equatable {
    let proxies: [String: ProxyGroup]
}

struct ProxyGroup: Decodable, Equatable {
    let name: String
    let type: String?
    let now: String?
    let all: [String]
    let testUrl: String?
    let timeout: Int?
    let icon: String?
    let hidden: Bool?
    let latestDelay: Int?

    init(
        name: String,
        type: String? = nil,
        now: String? = nil,
        all: [String],
        testUrl: String? = nil,
        timeout: Int? = nil,
        icon: String? = nil,
        hidden: Bool? = nil,
        latestDelay: Int? = nil)
    {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.testUrl = testUrl.trimmedNonEmpty
        self.timeout = timeout.positiveOrNil
        self.icon = icon.trimmedNonEmpty
        self.hidden = hidden
        self.latestDelay = latestDelay
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case now
        case all
        case testUrl
        case timeout
        case icon
        case hidden
        case history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.now = try container.decodeIfPresent(String.self, forKey: .now)
        self.all = try container.decodeIfPresent([String].self, forKey: .all) ?? []
        self.testUrl = try container.decodeIfPresent(String.self, forKey: .testUrl).trimmedNonEmpty
        self.timeout = container.decodeFlexibleInt(forKey: .timeout).positiveOrNil
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon).trimmedNonEmpty
        self.hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        self.latestDelay = Self.decodeLatestDelay(from: container)
    }

    private static func decodeLatestDelay(from container: KeyedDecodingContainer<CodingKeys>) -> Int? {
        guard var historyContainer = try? container.nestedUnkeyedContainer(forKey: .history) else {
            return nil
        }

        var latest: Int?
        while !historyContainer.isAtEnd {
            guard let entry = try? historyContainer.decode(ProxyDelayHistoryEntry.self) else {
                break
            }
            if let delay = entry.delay {
                latest = delay
            }
        }
        return latest
    }
}

private typealias ProxyDelayHistoryEntry = FlexibleDelayHistoryEntry

struct ConfigSnapshot: Codable, Equatable {
    struct TunConfig: Codable, Equatable {
        let enable: Bool?
        let stack: String?

        private enum CodingKeys: String, CodingKey {
            case enable
            case stack
        }

        init(enable: Bool?, stack: String?) {
            self.enable = enable
            self.stack = stack
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enable = container.decodeFlexibleBool(forKey: .enable)
            self.stack = container.decodeFlexibleString(forKey: .stack)
        }
    }

    let allowLan: Bool?
    let mode: String?
    let logLevel: String?
    let ipv6: Bool?
    let tcpConcurrent: Bool?
    let port: Int?
    let socksPort: Int?
    let redirPort: Int?
    let tproxyPort: Int?
    let mixedPort: Int?
    let tun: TunConfig?
    let externalController: String?

    var tunEnabled: Bool? {
        self.tun?.enable
    }

    private enum CodingKeys: String, CodingKey {
        case allowLan = "allow-lan"
        case mode
        case logLevel = "log-level"
        case ipv6
        case tcpConcurrent = "tcp-concurrent"
        case port
        case socksPort = "socks-port"
        case redirPort = "redir-port"
        case tproxyPort = "tproxy-port"
        case mixedPort = "mixed-port"
        case tun
        case externalController = "external-controller"
    }
}
