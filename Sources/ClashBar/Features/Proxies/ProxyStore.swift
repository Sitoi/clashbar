import Combine
import Foundation
import MihomoKit

@MainActor
final class ProxyStore: ObservableObject {
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var groupLatencyLoading: Set<String> = []
    @Published var proxyLatencyTesting: Set<ProxyLatencyTestKey> = []
    @Published var proxyDelaySamples: [String: [Int]] = [:]
    @Published var proxyNodeTypes: [String: String] = [:]
    @Published var isProxySyncing = false
    @Published var providerProxyCount = 0
    @Published var proxyProvidersDetail: [String: ProviderDetail] = [:]
    @Published var providerUpdating: Set<String> = []
    @Published var providerRefreshStatus: ProviderRefreshStatus = .idle

    // System Proxy State
    @Published var isSystemProxyEnabled: Bool = false
    @Published var systemProxyEnableIntentInFlight: Bool = false
    @Published var systemProxyHelperFailureReason: SystemProxyHelperFailureReason?
    @Published var systemProxyHelperFailureMessage: String?
    @Published var systemProxyBackgroundActivityAllowed: Bool?
    @Published var systemProxyHelperProcessRunning: Bool?
    @Published var systemProxyActiveDisplay: String?
    @Published var systemProxyOpenFailureHint: String?
    @Published var systemProxyExceptions: [EditableSystemProxyException] = []
    @Published var systemProxyNewException: String = ""
    var lastSavedSystemProxyExceptions: [String] = []
    var didCheckSystemProxyConsistencyOnLaunch: Bool = false

    /// TUN State
    @Published var isTunSyncing: Bool = false

    // Services
    let systemProxyService: SystemProxyService
    let tunPermissionService: TunPermissionService

    /// Session
    weak var session: AppViewModel?

    var isRemoteTarget: Bool {
        self.session?.isRemoteTarget ?? false
    }

    var isRuntimeRunning: Bool {
        self.session?.isRuntimeRunning ?? false
    }

    var resolvedBinaryPath: String? {
        self.session?.resolvedMihomoBinaryPath()
    }

    var coreDirectoryURL: URL {
        self.session?.workingDirectoryManager.coreDirectoryURL ?? URL(fileURLWithPath: "/")
    }

    var selectedConfigPath: String? {
        self.session?.configurationStore.selectedConfig?.path
    }

    var tunEnabled: Bool {
        get { self.session?.settingsStore.editableSettings.tunEnabled ?? false }
        set {
            guard let session else { return }
            session.settingsStore.editableSettings.tunEnabled = newValue
            session.persistEditableSettingsSnapshot()
        }
    }

    var controllerHost: String {
        self.session?.controllerHost() ?? "127.0.0.1"
    }

    var localExternalControllerDisplay: String {
        self.session?.localExternalControllerDisplay ?? "127.0.0.1"
    }

    var pendingCoreFeatureRecoveryState: CoreFeatureRecoveryState? {
        self.session?.pendingCoreFeatureRecoveryState
    }

    var systemProxyEnabledOnQuit: Bool {
        guard let session else { return false }
        return session.defaults.bool(forKey: session.systemProxyEnabledOnQuitKey)
    }

    func saveSystemProxyExceptionsToDefaults(_ exceptions: [String]) {
        guard let session else { return }
        session.defaults.set(exceptions, forKey: session.systemProxyExceptionsKey)
    }

    func getRuntimeConfigSnapshot() async throws -> ConfigSnapshot {
        guard let session else {
            throw CancellationError()
        }
        return try await session.fetchRuntimeConfigSnapshot()
    }

    func appendLog(level: String, message: String) {
        self.session?.appendLog(level: level, message: message)
    }

    init(
        systemProxyService: SystemProxyService = SystemProxyService(),
        tunPermissionService: TunPermissionService = TunPermissionService())
    {
        self.systemProxyService = systemProxyService
        self.tunPermissionService = tunPermissionService
    }

    private let defaultHealthcheckURL = "https://www.gstatic.com/generate_204"
    private let defaultHealthcheckTimeoutMilliseconds = 5000
    private var providerRefreshTask: Task<Void, Never>?
    private var providerRefreshGeneration: Int = 0

    var sortedProxyProviderNames: [String] {
        self.proxyProvidersDetail.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func filteredProxyGroups(hideHidden: Bool, currentMode: CoreMode) -> [ProxyGroup] {
        self.proxyGroups.filter { group in
            guard currentMode == .global || group.name.caseInsensitiveCompare("GLOBAL") != .orderedSame else {
                return false
            }
            return !hideHidden || group.hidden != true
        }
    }

    func resetPresentation() {
        self.proxyGroups = []
        self.proxyDelaySamples = [:]
        self.proxyNodeTypes = [:]
        self.groupLatencyLoading = []
        self.proxyLatencyTesting = []
        self.providerProxyCount = 0
        self.proxyProvidersDetail = [:]
        self.providerUpdating = []
        self.providerRefreshStatus = .idle
    }

    func switchProxy(group: String, target: String) async {
        do {
            let client = try self.resolveClient()
            try await client.requestNoResponse(.switchProxy(name: group, target: target))
            self.appendLog(level: "info", message: "Switched proxy group [\(group)] to [\(target)]")
            await self.refreshProxyGroups()
        } catch {
            self.appendLog(level: "error", message: "Switch proxy failed: \(error.localizedDescription)")
        }
    }

    func refreshProxyGroups() async {
        do {
            let client = try self.resolveClient()
            let response: ProxyGroupsResponse = try await client.request(.proxies)
            self.proxyGroups = response.proxies.values
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            // Ignore background error
        }
    }

    func refreshGroupLatency(_ group: ProxyGroup) async {
        self.groupLatencyLoading.insert(group.name)
        defer { self.groupLatencyLoading.remove(group.name) }

        let testURL = group.testUrl?.trimmedNonEmpty ?? self.defaultHealthcheckURL
        let timeout = group.timeout.flatMap { $0 > 0 ? $0 : nil } ?? self.defaultHealthcheckTimeoutMilliseconds

        do {
            let client = try self.resolveClient()
            let response: GroupDelayMeasurement = try await client.request(
                .groupDelay(name: group.name, url: testURL, timeout: timeout))
            self.applyMeasuredNodeDelays(response.values)
        } catch {
            self.appendLog(
                level: "error",
                message: "Latency check failed for group [\(group.name)]: \(error.localizedDescription)")
        }
    }

    func refreshAllGroupLatencies(includeHiddenGroups: Bool = false, currentMode: CoreMode = .rule) async {
        let modeScopedGroups = currentMode == .global
            ? self.proxyGroups
            : self.proxyGroups.filter { $0.name.caseInsensitiveCompare("GLOBAL") != .orderedSame }
        let groups = includeHiddenGroups
            ? modeScopedGroups
            : modeScopedGroups.filter { $0.hidden != true }

        await withTaskGroup(of: Void.self) { taskGroup in
            for group in groups {
                taskGroup.addTask { [weak self] in
                    await self?.refreshGroupLatency(group)
                }
            }
        }
    }

    func isProxyLatencyTesting(group: String, node: String) -> Bool {
        self.proxyLatencyTesting.contains(ProxyLatencyTestKey(group: group, node: node))
    }

    func refreshProxyLatency(group: String, node: String) async {
        let key = ProxyLatencyTestKey(group: group, node: node)
        guard !self.proxyLatencyTesting.contains(key) else { return }

        self.proxyLatencyTesting.insert(key)
        defer { self.proxyLatencyTesting.remove(key) }

        let proxyGroup = self.proxyGroups.first { $0.name == group }
        let testURL = proxyGroup?.testUrl?.trimmedNonEmpty ?? self.defaultHealthcheckURL
        let timeout = proxyGroup?.timeout.flatMap { $0 > 0 ? $0 : nil } ?? self.defaultHealthcheckTimeoutMilliseconds

        do {
            let client = try self.resolveClient()
            let response: DelayMeasurement = try await client.request(
                .proxyDelay(name: node, url: testURL, timeout: timeout))
            guard let value = response.value else { return }
            self.applyMeasuredNodeDelays([node: value])
        } catch {
            self.appendLog(
                level: "error",
                message: "Latency check failed for node [\(node)]: \(error.localizedDescription)")
        }
    }

    func applyMeasuredNodeDelays(_ delays: [String: Int]) {
        guard !delays.isEmpty else { return }

        var samples = self.proxyDelaySamples
        for (name, delay) in delays {
            var series = samples[name] ?? []
            series.append(delay)
            if series.count > ProxyDelayHistory.limit {
                series = Array(series.suffix(ProxyDelayHistory.limit))
            }
            samples[name] = series
        }
        self.proxyDelaySamples = samples
    }

    func delayText(group: String, node: String, fallbackToGroupHistory: Bool = false) -> String {
        guard let value = self.delayValue(
            group: group,
            node: node,
            fallbackToGroupHistory: fallbackToGroupHistory)
        else { return "--" }
        if value == 0 {
            return "Timeout"
        }
        return "\(value) ms"
    }

    func delayValue(group: String, node: String, fallbackToGroupHistory: Bool = false) -> Int? {
        self.delaySamples(group: group, node: node, fallbackToGroupHistory: fallbackToGroupHistory).last
    }

    func delaySamples(group: String, node: String, fallbackToGroupHistory: Bool = false) -> [Int] {
        for name in self.proxySelectionChain(startingAt: node).reversed() {
            if let samples = self.proxyDelaySamples[name], !samples.isEmpty {
                return samples
            }
        }
        if fallbackToGroupHistory {
            for name in self.proxySelectionChain(startingAt: group).reversed() {
                if let samples = self.proxyDelaySamples[name], !samples.isEmpty {
                    return samples
                }
            }
        }
        return []
    }

    private func proxySelectionChain(startingAt start: String) -> [String] {
        var chain: [String] = []
        var current = start
        var seen = Set<String>()
        while seen.insert(current).inserted {
            chain.append(current)
            guard let nested = self.proxyGroups.first(where: { $0.name == current }),
                  !nested.all.isEmpty,
                  let next = nested.now?.trimmedNonEmpty
            else {
                break
            }
            current = next
        }
        return chain
    }

    func updateProxyProvider(name: String) async {
        guard !self.providerUpdating.contains(name) else { return }
        self.providerUpdating.insert(name)
        defer { self.providerUpdating.remove(name) }

        do {
            let client = try self.resolveClient()
            try await client.requestNoResponse(.updateProxyProvider(name: name))
            self.appendLog(level: "info", message: "Proxy provider [\(name)] updated")
            await self.refreshProxyProviders()
        } catch {
            self.appendLog(
                level: "error",
                message: "Update proxy provider [\(name)] failed: \(error.localizedDescription)")
        }
    }

    func refreshProxyProviders() async {
        do {
            let client = try self.resolveClient()
            let summary: ProviderSummary = try await client.request(.proxyProviders)
            let filtered = summary.providers.filter { key, detail in
                let resolvedName = detail.name.trimmedNonEmpty ?? key
                return resolvedName.caseInsensitiveCompare("default") != .orderedSame
                    && detail.vehicleType.trimmedOrEmpty.caseInsensitiveCompare("Compatible") != .orderedSame
            }
            self.proxyProvidersDetail = filtered
            self.providerProxyCount = filtered.count
        } catch {
            // Ignore background error
        }
    }

    func enqueueProviderRefresh(trigger: ProviderRefreshTrigger) {
        self.cancelProviderRefresh(reason: "superseded")
        self.providerRefreshGeneration += 1
        let generation = self.providerRefreshGeneration
        self.providerRefreshTask = Task { [weak self] in
            await self?.runProviderRefreshInBackground(trigger: trigger, generation: generation)
        }
    }

    func cancelProviderRefresh(reason: String) {
        guard self.providerRefreshTask != nil else { return }
        self.providerRefreshTask?.cancel()
        self.providerRefreshTask = nil
        self.providerRefreshStatus = ProviderRefreshStatus(
            phase: .cancelled,
            trigger: self.providerRefreshStatus.trigger,
            progressDone: self.providerRefreshStatus.progressDone,
            progressTotal: self.providerRefreshStatus.progressTotal,
            message: reason,
            updatedAt: Date())
    }

    private func runProviderRefreshInBackground(trigger: ProviderRefreshTrigger, generation: Int) async {
        self.providerRefreshStatus = ProviderRefreshStatus(
            phase: .updating,
            trigger: trigger,
            progressDone: 0,
            progressTotal: 1,
            message: nil,
            updatedAt: Date())

        do {
            let client = try self.resolveClient()
            let summary: ProviderSummary = try await client.request(.proxyProviders)
            let names = summary.providers.keys.sorted()
            let total = names.count

            for (index, name) in names.enumerated() {
                if Task.isCancelled || self.providerRefreshGeneration != generation {
                    return
                }
                self.providerRefreshStatus = ProviderRefreshStatus(
                    phase: .updating,
                    trigger: trigger,
                    progressDone: index,
                    progressTotal: total,
                    message: name,
                    updatedAt: Date())
                do {
                    try await client.requestNoResponse(.updateProxyProvider(name: name))
                } catch {
                    // Continue with next
                }
            }

            guard self.providerRefreshGeneration == generation else { return }
            await self.refreshProxyProviders()
            self.providerRefreshStatus = ProviderRefreshStatus(
                phase: .succeeded,
                trigger: trigger,
                progressDone: total,
                progressTotal: total,
                message: nil,
                updatedAt: Date())
        } catch {
            guard self.providerRefreshGeneration == generation else { return }
            self.providerRefreshStatus = ProviderRefreshStatus(
                phase: .failed,
                trigger: trigger,
                progressDone: 0,
                progressTotal: 0,
                message: error.localizedDescription,
                updatedAt: Date())
        }
    }

    func resolveClient() throws -> MihomoAPIService {
        guard let session else {
            throw APIError.clientUnavailable
        }
        return try session.clientOrThrow()
    }

    func tr(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: .zhHans, args: args)
    }

    func tr(_ key: String) -> String {
        L10n.t(key, language: .zhHans)
    }
}
