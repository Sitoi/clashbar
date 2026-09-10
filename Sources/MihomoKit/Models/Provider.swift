import Foundation

public struct ProviderSummary: Decodable, Equatable, Sendable {
    public let providers: [String: ProviderDetail]

    public init(providers: [String: ProviderDetail]) {
        self.providers = providers
    }
}

public struct ProviderDetail: Decodable, Equatable, Sendable {
    public let name: String?
    public let vehicleType: String?
    public let testUrl: String?
    public let timeout: Int?
    public let updatedAt: String?
    public let ruleCount: Int?
    public let subscriptionInfo: ProviderSubscriptionInfo?
    public let proxies: [ProviderProxyNode]?

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

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func with(proxies: [ProviderProxyNode]?) -> ProviderDetail {
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

public struct ProviderSubscriptionInfo: Decodable, Equatable, Sendable {
    public let upload: Int64?
    public let download: Int64?
    public let total: Int64?
    public let expire: Int64?

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

    public init(
        upload: Int64? = nil,
        download: Int64? = nil,
        total: Int64? = nil,
        expire: Int64? = nil)
    {
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.upload = c.decodeInt64WithFallback(primary: .upload, fallback: .uploadUpper)
        self.download = c.decodeInt64WithFallback(primary: .download, fallback: .downloadUpper)
        self.total = c.decodeInt64WithFallback(primary: .total, fallback: .totalUpper)
        self.expire = c.decodeInt64WithFallback(primary: .expire, fallback: .expireUpper)
    }
}

public struct ProviderProxyNode: Decodable, Equatable, Sendable {
    public let name: String
    public let type: String?
    public let delayHistory: [Int]

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case history
    }

    public init(name: String, type: String? = nil, delayHistory: [Int] = []) {
        self.name = name
        self.type = type
        self.delayHistory = delayHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "-"
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.delayHistory = container.decodeDelayHistory(forKey: .history)
    }
}

package struct FlexibleDelayHistoryEntry: Decodable, Equatable, Sendable {
    package let delay: Int?

    private enum CodingKeys: String, CodingKey {
        case delay
    }

    package init(delay: Int?) {
        self.delay = delay
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.delay = container.decodeFlexibleInt(forKey: .delay)
    }
}
