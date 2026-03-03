import Foundation

struct ProviderSummary: Decodable, Equatable {
    let providers: [String: ProviderDetail]
}

struct ProviderDetail: Decodable, Equatable {
    let name: String?
    let vehicleType: String?
    let updatedAt: String?
    let ruleCount: Int?
    let subscriptionInfo: ProviderSubscriptionInfo?
    let proxies: [ProviderProxyNode]?

    private enum CodingKeys: String, CodingKey {
        case name
        case vehicleType
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
        updatedAt: String?,
        ruleCount: Int?,
        subscriptionInfo: ProviderSubscriptionInfo?,
        proxies: [ProviderProxyNode]?)
    {
        self.name = name
        self.vehicleType = vehicleType
        self.updatedAt = updatedAt
        self.ruleCount = ruleCount
        self.subscriptionInfo = subscriptionInfo
        self.proxies = proxies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.ruleCount = try container.decodeIfPresent(Int.self, forKey: .ruleCount)
            ?? container.decodeIfPresent(Int.self, forKey: .rulesCount)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
        self.subscriptionInfo = try container.decodeIfPresent(ProviderSubscriptionInfo.self, forKey: .subscriptionInfo)
        self.proxies = try container.decodeIfPresent([ProviderProxyNode].self, forKey: .proxies)
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.upload = try container.decodeIfPresent(Int64.self, forKey: .upload)
            ?? container.decodeIfPresent(Int64.self, forKey: .uploadUpper)
        self.download = try container.decodeIfPresent(Int64.self, forKey: .download)
            ?? container.decodeIfPresent(Int64.self, forKey: .downloadUpper)
        self.total = try container.decodeIfPresent(Int64.self, forKey: .total)
            ?? container.decodeIfPresent(Int64.self, forKey: .totalUpper)
        self.expire = try container.decodeIfPresent(Int64.self, forKey: .expire)
            ?? container.decodeIfPresent(Int64.self, forKey: .expireUpper)
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

struct ProviderProxyDelayHistoryEntry: Decodable, Equatable {
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
