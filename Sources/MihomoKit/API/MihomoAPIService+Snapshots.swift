import Foundation

extension MihomoAPIService {
    public func fetchMediumFrequencySnapshot(
        includeProxyGroups: Bool,
        includeVersion: Bool = true) async throws -> MediumFrequencySnapshot
    {
        async let versionInfo: VersionInfo? = includeVersion ? self.request(.version) : nil
        async let configSnapshot: ConfigSnapshot = self.request(.getConfigs)
        async let proxyGroups: ProxyGroupsAndProvidersSnapshot? = includeProxyGroups
            ? self.fetchProxyGroupsAndProviders() : nil
        return try await MediumFrequencySnapshot(
            versionInfo: versionInfo,
            configSnapshot: configSnapshot,
            proxyGroupsPayload: proxyGroups)
    }

    public func fetchProxyGroupsAndProviders() async throws -> ProxyGroupsAndProvidersSnapshot {
        let groups: ProxyGroupsResponse = try await self.request(.proxies)
        do {
            let providers: ProviderSummary = try await self.request(.proxyProviders)
            return ProxyGroupsAndProvidersSnapshot(groups: groups, providers: providers.providers, providersError: nil)
        } catch {
            return ProxyGroupsAndProvidersSnapshot(groups: groups, providers: [:], providersError: error)
        }
    }

    public func fetchProvidersAndRules() async throws -> ProvidersAndRulesSnapshot {
        async let proxyProviders: ProviderSummary = self.request(.proxyProviders)
        async let ruleProviders: ProviderSummary = self.request(.ruleProviders)
        async let rules: RulesSummary = self.request(.rules)
        return try await ProvidersAndRulesSnapshot(
            proxyProviders: proxyProviders,
            ruleProviders: ruleProviders,
            rules: rules)
    }
}
