import Combine
import Foundation
import MihomoKit
import SwiftUI

@MainActor
final class RulesStore: ObservableObject {
    @Published var rulesCount: Int = 0
    @Published var providerRuleCount: Int = 0
    @Published var ruleProviders: [String: ProviderDetail] = [:]
    @Published var ruleItems: [RuleItem] = []
    @Published var isRuleProvidersRefreshing: Bool = false

    @Published var filterText: String = "" {
        didSet { self.updateVisibleRules() }
    }

    @Published var typeFilter: RulesTypeFilter = .all {
        didSet { self.updateVisibleRules() }
    }

    @Published var policyFilter: RulePolicyOption = .all {
        didSet { self.updateVisibleRules() }
    }

    @Published var groupByPolicy: Bool = false {
        didSet { self.updateVisibleRules() }
    }

    @Published private(set) var output: PresentRulesOutput = .empty

    var apiClientProvider: (() throws -> MihomoAPIService)?
    var logHandler: ((_ level: String, _ message: String) -> Void)?

    func setRulesAndProviders(
        rules: [RuleItem],
        totalCount: Int,
        providers: [String: ProviderDetail])
    {
        self.ruleItems = rules
        self.rulesCount = totalCount
        self.ruleProviders = providers
        self.providerRuleCount = providers.count
        self.updateVisibleRules()
    }

    func resetPresentation() {
        self.ruleItems = []
        self.rulesCount = 0
        self.ruleProviders = [:]
        self.providerRuleCount = 0
        self.isRuleProvidersRefreshing = false
        self.output = .empty
    }

    func reset() {
        self.resetPresentation()
    }

    func updateVisibleRules() {
        let items = self.ruleItems
        let providers = self.ruleProviders
        let policyOptions = self.makePolicyOptions(from: items)
        let keyword = self.filterText.trimmed
        let currentPolicyFilter = self.policyFilter
        let currentTypeFilter = self.typeFilter

        let base: [RuleItem] = if keyword.isEmpty, currentPolicyFilter.isAll {
            items
        } else {
            items.filter { rule in
                guard currentPolicyFilter.isAll || rule.proxy.trimmedOrEmpty == currentPolicyFilter.name
                else { return false }
                guard keyword.isEmpty || self.ruleMatchesKeyword(rule, keyword: keyword) else {
                    return false
                }
                return true
            }
        }

        let typeCounts = self.makeTypeCounts(from: base)
        let filtered = currentTypeFilter == .all ? base : base.filter { currentTypeFilter.matches($0.type) }

        let next = PresentRulesOutput(
            rules: filtered,
            groups: self.groupByPolicy ? self.makeGroups(from: filtered) : [],
            providerLookup: self.makeProviderLookup(from: providers),
            policyOptions: policyOptions,
            typeCounts: typeCounts)

        if !self.policyFilter.isAll, !next.policyOptions.contains(self.policyFilter) {
            self.policyFilter = .all
        }

        if next != self.output {
            self.output = next
        }
    }

    func updateRuleProvider(name: String) async {
        do {
            let client = try self.resolveClient()
            try await client.requestNoResponse(.updateRuleProvider(name: name))
            await self.reloadRulesAndProviders()
        } catch {
            self.logHandler?("error", "Update rule provider \(name) failed: \(error.localizedDescription)")
        }
    }

    func refreshRuleProviders() async {
        guard !self.isRuleProvidersRefreshing else { return }
        self.isRuleProvidersRefreshing = true
        defer { self.isRuleProvidersRefreshing = false }

        do {
            let client = try self.resolveClient()
            let summary: ProviderSummary = try await client.request(.ruleProviders)
            let names = summary.providers.keys.sorted()
            for name in names {
                do {
                    try await client.requestNoResponse(.updateRuleProvider(name: name))
                } catch {
                    self.logHandler?("error", "Update rule provider \(name) failed: \(error.localizedDescription)")
                }
            }
            await self.reloadRulesAndProviders()
        } catch {
            self.logHandler?("error", "Fetch rule providers failed: \(error.localizedDescription)")
        }
    }

    func reloadRulesAndProviders() async {
        do {
            let client = try self.resolveClient()
            let snapshot = try await client.fetchProvidersAndRules()
            self.setRulesAndProviders(
                rules: snapshot.rules.rules,
                totalCount: snapshot.rules.totalCount,
                providers: snapshot.ruleProviders.providers)
        } catch {
            self.logHandler?("error", "Reload rules failed: \(error.localizedDescription)")
        }
    }

    private func resolveClient() throws -> MihomoAPIService {
        guard let provider = self.apiClientProvider else {
            throw APIError.clientUnavailable
        }
        return try provider()
    }

    private func makeTypeCounts(from rules: [RuleItem]) -> [RulesTypeFilter: Int] {
        var counts: [RulesTypeFilter: Int] = [.all: rules.count]
        for rule in rules {
            let category = RulesTypeFilter.categorize(rule.type)
            counts[category, default: 0] += 1
        }
        return counts
    }

    private func makeGroups(from rules: [RuleItem]) -> [RuleGroup] {
        Dictionary(grouping: rules, by: \.proxy.trimmedOrEmpty)
            .map { RuleGroup(policy: $0.key, rules: $0.value) }
            .sorted { lhs, rhs in
                lhs.rules.count != rhs.rules.count
                    ? lhs.rules.count > rhs.rules.count
                    : lhs.policy.localizedStandardCompare(rhs.policy) == .orderedAscending
            }
    }

    private func ruleMatchesKeyword(_ rule: RuleItem, keyword: String) -> Bool {
        rule.payload?.localizedStandardContains(keyword) == true
            || rule.type?.localizedStandardContains(keyword) == true
            || rule.proxy?.localizedStandardContains(keyword) == true
    }

    private func makePolicyOptions(from items: [RuleItem]) -> [RulePolicyOption] {
        let names = Set(items.compactMap(\.proxy.trimmedNonEmpty))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [.all] + names.map { RulePolicyOption(name: $0) }
    }

    private func makeProviderLookup(from providers: [String: ProviderDetail]) -> [String: ProviderDetail] {
        var map: [String: ProviderDetail] = [:]
        map.reserveCapacity(providers.count * 2)

        for (key, detail) in providers {
            map[key.lowercased()] = detail
            if let name = detail.name.trimmedNonEmpty {
                map[name.lowercased()] = detail
            }
        }

        return map
    }
}
