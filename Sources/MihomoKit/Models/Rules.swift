import Foundation

public struct RulesSummary: Decodable, Equatable, Sendable {
    public static let retainedRuleLimit = 20000

    public let rules: [RuleItem]
    public let totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case rules
    }

    public init(rules: [RuleItem], totalCount: Int? = nil) {
        self.rules = rules
        self.totalCount = totalCount ?? rules.count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard var rulesContainer = try? container.nestedUnkeyedContainer(forKey: .rules) else {
            self.rules = []
            self.totalCount = 0
            return
        }

        var retained: [RuleItem] = []
        retained.reserveCapacity(min(Self.retainedRuleLimit, rulesContainer.count ?? Self.retainedRuleLimit))

        var totalCount = 0
        while !rulesContainer.isAtEnd {
            let rule = try rulesContainer.decode(RuleItem.self)
            if retained.count < Self.retainedRuleLimit {
                retained.append(rule)
            }
            totalCount += 1
        }

        self.rules = retained
        self.totalCount = totalCount
    }
}

public struct RuleItem: Decodable, Hashable, Sendable {
    public let type: String?
    public let payload: String?
    public let proxy: String?

    public init(type: String?, payload: String?, proxy: String?) {
        self.type = type
        self.payload = payload
        self.proxy = proxy
    }
}
