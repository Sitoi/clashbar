import Foundation

struct SSIDStrategyRule: Codable, Equatable {
    var ssid: String
    var configFileName: String
}

extension SSIDStrategyRule {
    static func normalized(_ rules: [SSIDStrategyRule]) -> [SSIDStrategyRule] {
        var normalizedRules: [SSIDStrategyRule] = []
        var indexesBySSID: [String: Int] = [:]

        for rule in rules {
            let normalizedSSID = rule.ssid.trimmed
            let normalizedConfigFileName = rule.configFileName.trimmed
            guard !normalizedSSID.isEmpty, !normalizedConfigFileName.isEmpty else { continue }

            let normalizedRule = SSIDStrategyRule(
                ssid: normalizedSSID,
                configFileName: normalizedConfigFileName)

            if let existingIndex = indexesBySSID[normalizedSSID] {
                normalizedRules[existingIndex] = normalizedRule
            } else {
                indexesBySSID[normalizedSSID] = normalizedRules.count
                normalizedRules.append(normalizedRule)
            }
        }

        return normalizedRules
    }

    static func upserting(
        ssid: String,
        configFileName: String,
        into rules: [SSIDStrategyRule]) -> [SSIDStrategyRule]
    {
        let normalizedSSID = ssid.trimmed
        let normalizedConfigFileName = configFileName.trimmed
        guard !normalizedSSID.isEmpty, !normalizedConfigFileName.isEmpty else {
            return Self.normalized(rules)
        }

        return Self.normalized(rules + [SSIDStrategyRule(
            ssid: normalizedSSID,
            configFileName: normalizedConfigFileName)])
    }

    static func removing(ssid: String, from rules: [SSIDStrategyRule]) -> [SSIDStrategyRule] {
        let normalizedSSID = ssid.trimmed
        guard !normalizedSSID.isEmpty else {
            return Self.normalized(rules)
        }

        return Self.normalized(rules).filter { $0.ssid != normalizedSSID }
    }

    enum Resolution: Equatable {
        case noAction
        case switchToConfig(String)
        case missingConfig(String)
    }

    static func resolveTargetConfig(
        currentSSID: String?,
        currentConfigName: String?,
        rules: [SSIDStrategyRule],
        availableConfigNames: [String]) -> Resolution
    {
        guard let normalizedSSID = currentSSID?.trimmedNonEmpty else {
            return .noAction
        }

        let normalizedRules = self.normalized(rules)
        guard let matchedRule = normalizedRules.first(where: { $0.ssid == normalizedSSID }) else {
            return .noAction
        }

        let targetConfigName = matchedRule.configFileName
        guard Set(availableConfigNames.map(\.trimmed)).contains(targetConfigName) else {
            return .missingConfig(targetConfigName)
        }

        if targetConfigName == currentConfigName?.trimmed {
            return .noAction
        }

        return .switchToConfig(targetConfigName)
    }
}
