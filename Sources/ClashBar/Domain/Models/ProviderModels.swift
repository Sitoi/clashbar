import Foundation

struct ProviderSummary: Decodable, Equatable {
    let providers: [String: ProviderDetail]
}

struct ProviderDetail: Decodable, Equatable {
    let name: String?
    let vehicleType: String?
    let testUrl: String?
    let timeout: Int?
    let updatedAt: String?
    let ruleCount: Int?
    let subscriptionInfo: ProviderSubscriptionInfo?
    let proxies: [ProviderProxyNode]?

    private enum CodingKeys: String, CodingKey {
        case name
        case vehicleType
        case testUrl
        case timeout
        case updatedAt
        case ruleCount
        case rulesCount
        case count
        case subscriptionInfo
        case proxies
    }

    init(
        name: String?,
        vehicleType: String?,
        testUrl: String?,
        timeout: Int?,
        updatedAt: String?,
        ruleCount: Int?,
        subscriptionInfo: ProviderSubscriptionInfo?,
        proxies: [ProviderProxyNode]?)
    {
        self.name = name
        self.vehicleType = vehicleType
        self.testUrl = testUrl.trimmedNonEmpty
        self.timeout = timeout.positiveOrNil
        self.updatedAt = updatedAt
        self.ruleCount = ruleCount
        self.subscriptionInfo = subscriptionInfo
        self.proxies = proxies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
        self.testUrl = try container.decodeIfPresent(String.self, forKey: .testUrl).trimmedNonEmpty
        self.timeout = container.decodeFlexibleInt(forKey: .timeout).positiveOrNil
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.ruleCount = try container.decodeIfPresent(Int.self, forKey: .ruleCount)
            ?? container.decodeIfPresent(Int.self, forKey: .rulesCount)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
        self.subscriptionInfo = try container.decodeIfPresent(ProviderSubscriptionInfo.self, forKey: .subscriptionInfo)
        self.proxies = try container.decodeIfPresent([ProviderProxyNode].self, forKey: .proxies)
    }

    func with(proxies: [ProviderProxyNode]?) -> ProviderDetail {
        ProviderDetail(
            name: self.name,
            vehicleType: self.vehicleType,
            testUrl: self.testUrl,
            timeout: self.timeout,
            updatedAt: self.updatedAt,
            ruleCount: self.ruleCount,
            subscriptionInfo: self.subscriptionInfo,
            proxies: proxies)
    }
}

struct ProviderSubscriptionInfo: Decodable, Equatable {
    let upload: Int64?
    let download: Int64?
    let total: Int64?
    let expire: Int64?

    private enum CodingKeys: String, CodingKey {
        case upload
        case download
        case total
        case expire
        case uploadUpper = "Upload"
        case downloadUpper = "Download"
        case totalUpper = "Total"
        case expireUpper = "Expire"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.upload = c.decodeInt64WithFallback(primary: .upload, fallback: .uploadUpper)
        self.download = c.decodeInt64WithFallback(primary: .download, fallback: .downloadUpper)
        self.total = c.decodeInt64WithFallback(primary: .total, fallback: .totalUpper)
        self.expire = c.decodeInt64WithFallback(primary: .expire, fallback: .expireUpper)
    }
}

struct ProviderProxyNode: Decodable, Equatable {
    let name: String
    let history: [ProviderProxyDelayHistoryEntry]?

    private enum CodingKeys: String, CodingKey {
        case name
        case history
    }

    init(name: String, history: [ProviderProxyDelayHistoryEntry]? = nil) {
        self.name = name
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "-"
        self.history = try container.decodeIfPresent([ProviderProxyDelayHistoryEntry].self, forKey: .history)
    }
}

typealias ProviderProxyDelayHistoryEntry = FlexibleDelayHistoryEntry

struct FlexibleDelayHistoryEntry: Decodable, Equatable {
    let delay: Int?

    private enum CodingKeys: String, CodingKey {
        case delay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.delay = container.decodeFlexibleInt(forKey: .delay)
    }
}
