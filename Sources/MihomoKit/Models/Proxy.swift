import Foundation

public enum ProxyDelayHistory {
    public static let limit = 4

    public static func merge(
        api: [String: [Int]],
        previous: [String: [Int]]) -> [String: [Int]]
    {
        var merged = api
        for (name, existing) in previous {
            guard !existing.isEmpty else { continue }
            guard let apiSamples = api[name], !apiSamples.isEmpty else {
                merged[name] = Array(existing.suffix(ProxyDelayHistory.limit))
                continue
            }
            merged[name] = Self.mergeDelaySeries(api: apiSamples, previous: existing)
        }
        return merged
    }

    private static func mergeDelaySeries(api: [Int], previous: [Int]) -> [Int] {
        let limit = ProxyDelayHistory.limit

        func overlap(from earlier: [Int], to later: [Int]) -> Int {
            let maximum = min(earlier.count, later.count)
            guard maximum > 0 else { return 0 }
            for count in stride(from: maximum, through: 1, by: -1)
                where earlier.suffix(count).elementsEqual(later.prefix(count))
            {
                return count
            }
            return 0
        }

        let previousFollowsAPI = overlap(from: api, to: previous)
        let apiFollowsPrevious = overlap(from: previous, to: api)

        let samples: [Int] = if previousFollowsAPI > apiFollowsPrevious {
            previous.count > previousFollowsAPI ? previous : api
        } else if apiFollowsPrevious > previousFollowsAPI {
            api.count > apiFollowsPrevious ? api : previous
        } else if previousFollowsAPI > 0 || previous.last == api.last || previous.count >= api.count {
            previous.count >= api.count ? previous : api
        } else {
            api + previous.suffix(1)
        }
        return Array(samples.suffix(limit))
    }
}

public struct ProxyGroupsResponse: Decodable, Equatable, Sendable {
    public let proxies: [String: ProxyGroup]

    public init(proxies: [String: ProxyGroup]) {
        self.proxies = proxies
    }
}

public struct ProxyGroup: Decodable, Equatable, Sendable {
    public let name: String
    public let type: String?
    public let now: String?
    public let all: [String]
    public let testUrl: String?
    public let timeout: Int?
    public let icon: String?
    public let hidden: Bool?
    public let delayHistory: [Int]

    public init(
        name: String,
        type: String? = nil,
        now: String? = nil,
        all: [String],
        testUrl: String? = nil,
        timeout: Int? = nil,
        icon: String? = nil,
        hidden: Bool? = nil,
        delayHistory: [Int] = [])
    {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.testUrl = testUrl.trimmedNonEmpty
        self.timeout = timeout.positiveOrNil
        self.icon = icon.trimmedNonEmpty
        self.hidden = hidden
        self.delayHistory = delayHistory
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.now = try container.decodeIfPresent(String.self, forKey: .now)
        self.all = try container.decodeIfPresent([String].self, forKey: .all) ?? []
        self.testUrl = try container.decodeIfPresent(String.self, forKey: .testUrl).trimmedNonEmpty
        self.timeout = container.decodeFlexibleInt(forKey: .timeout).positiveOrNil
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon).trimmedNonEmpty
        self.hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        self.delayHistory = container.decodeDelayHistory(forKey: .history)
    }
}
