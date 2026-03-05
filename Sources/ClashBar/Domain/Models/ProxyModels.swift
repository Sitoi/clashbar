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
        self.testUrl = Self.normalizedText(testUrl)
        self.timeout = Self.normalizedTimeout(timeout)
        self.icon = Self.normalizedIcon(icon)
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
        self.testUrl = try Self.normalizedText(container.decodeIfPresent(String.self, forKey: .testUrl))
        self.timeout = Self.decodeTimeout(from: container)
        self.icon = Self.normalizedIcon(try? container.decodeIfPresent(String.self, forKey: .icon))
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

    private static func normalizedIcon(_ value: String?) -> String? {
        self.normalizedText(value)
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func decodeTimeout(from container: KeyedDecodingContainer<CodingKeys>) -> Int? {
        if let timeout = try? container.decodeIfPresent(Int.self, forKey: .timeout) {
            return self.normalizedTimeout(timeout)
        }
        if let timeout64 = try? container.decodeIfPresent(Int64.self, forKey: .timeout) {
            return Self.normalizedTimeout(Int(timeout64))
        }
        if let timeoutText = try? container.decodeIfPresent(String.self, forKey: .timeout),
           let timeout = Int(timeoutText)
        {
            return Self.normalizedTimeout(timeout)
        }
        return nil
    }

    private static func normalizedTimeout(_ timeout: Int?) -> Int? {
        guard let timeout, timeout > 0 else { return nil }
        return timeout
    }
}

private struct ProxyDelayHistoryEntry: Decodable, Equatable {
    let delay: Int?

    private enum CodingKeys: String, CodingKey {
        case delay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Int.self, forKey: .delay) {
            self.delay = value
            return
        }
        if let value = try container.decodeIfPresent(Int64.self, forKey: .delay) {
            self.delay = Int(value)
            return
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .delay),
           let intValue = Int(value)
        {
            self.delay = intValue
            return
        }
        self.delay = nil
    }
}

struct ConfigSnapshot: Codable, Equatable {
    struct TunConfig: Codable, Equatable {
        let enable: Bool?
    }

    let allowLan: Bool?
    let mode: String?
    let logLevel: String?
    let ipv6: Bool?
    let unifiedDelay: Bool?
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
        case unifiedDelay = "unified-delay"
        case port
        case socksPort = "socks-port"
        case redirPort = "redir-port"
        case tproxyPort = "tproxy-port"
        case mixedPort = "mixed-port"
        case tun
        case externalController = "external-controller"
    }
}
