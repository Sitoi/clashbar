import Foundation

struct RulesSummary: Decodable, Equatable {
    static let retainedRuleLimit = 100

    let rules: [RuleItem]
    let totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case rules
    }

    init(rules: [RuleItem], totalCount: Int? = nil) {
        self.rules = rules
        self.totalCount = totalCount ?? rules.count
    }

    init(from decoder: Decoder) throws {
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

struct RuleItem: Codable, Equatable, Identifiable {
    /// Stable identity derived from content, used by ForEach to avoid unnecessary view teardown.
    var id: String { "\(type ?? ""):\(payload ?? ""):\(proxy ?? "")" }
    let type: String?
    let payload: String?
    let proxy: String?
}
