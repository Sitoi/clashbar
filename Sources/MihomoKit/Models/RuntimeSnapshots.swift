import Foundation

public struct MediumFrequencySnapshot: Sendable {
    public let versionInfo: VersionInfo?
    public let configSnapshot: ConfigSnapshot
    public let proxyGroupsPayload: ProxyGroupsAndProvidersSnapshot?

    public init(
        versionInfo: VersionInfo?,
        configSnapshot: ConfigSnapshot,
        proxyGroupsPayload: ProxyGroupsAndProvidersSnapshot?)
    {
        self.versionInfo = versionInfo
        self.configSnapshot = configSnapshot
        self.proxyGroupsPayload = proxyGroupsPayload
    }
}

public struct ProxyGroupsAndProvidersSnapshot: Sendable {
    public let groups: ProxyGroupsResponse
    public let providers: [String: ProviderDetail]
    public let providersError: Error?

    public init(
        groups: ProxyGroupsResponse,
        providers: [String: ProviderDetail],
        providersError: Error?)
    {
        self.groups = groups
        self.providers = providers
        self.providersError = providersError
    }
}

public struct ProvidersAndRulesSnapshot: Sendable {
    public let proxyProviders: ProviderSummary
    public let ruleProviders: ProviderSummary
    public let rules: RulesSummary

    public init(
        proxyProviders: ProviderSummary,
        ruleProviders: ProviderSummary,
        rules: RulesSummary)
    {
        self.proxyProviders = proxyProviders
        self.ruleProviders = ruleProviders
        self.rules = rules
    }
}
