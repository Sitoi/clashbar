import Foundation
import MihomoKit

enum RulesTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case domain
    case ip
    case ruleSet
    case other

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .all:
            "ui.rules.type.all"
        case .domain:
            "ui.rules.type.domain"
        case .ip:
            "ui.rules.type.ip"
        case .ruleSet:
            "ui.rules.type.ruleset"
        case .other:
            "ui.rules.type.other"
        }
    }

    static func categorize(_ type: String?) -> RulesTypeFilter {
        guard let type, !type.isEmpty else { return .other }
        let normalized = type.lowercased()
        if normalized.contains("rule-set") || normalized.contains("ruleset") {
            return .ruleSet
        }
        if normalized.contains("domain") || normalized.contains("geosite") {
            return .domain
        }
        if normalized.contains("ip") || normalized.contains("geoip") {
            return .ip
        }
        return .other
    }

    func matches(_ type: String?) -> Bool {
        self == .all || self == Self.categorize(type)
    }
}

struct RulePolicyOption: Hashable, Identifiable, Sendable {
    let name: String

    var id: String {
        self.name
    }

    var isAll: Bool {
        self.name.isEmpty
    }

    static let all = RulePolicyOption(name: "")
}

struct RuleGroup: Equatable, Identifiable, Sendable {
    let policy: String
    let rules: [RuleItem]

    var id: String {
        self.policy
    }
}

struct PresentRulesOutput: Equatable, Sendable {
    let rules: [RuleItem]
    let groups: [RuleGroup]
    let providerLookup: [String: ProviderDetail]
    let policyOptions: [RulePolicyOption]
    let typeCounts: [RulesTypeFilter: Int]

    static let empty = PresentRulesOutput(
        rules: [], groups: [], providerLookup: [:], policyOptions: [.all], typeCounts: [:])
}
