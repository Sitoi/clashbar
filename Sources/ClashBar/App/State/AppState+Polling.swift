import Foundation

@MainActor
extension AppState {
    func startPolling() {
        self.teardownStreams()
        self.ensurePeriodicTasksForCurrentVisibility()
        self.updateDataAcquisitionPolicy()
    }

    func cancelPolling() {
        self.teardownStreams()
    }

    private func teardownStreams() {
        mediumFrequencyTask?.cancel()
        lowFrequencyTask?.cancel()
        for kind in StreamKind.allCases {
            cancelStream(kind)
        }
        mediumFrequencyTask = nil
        lowFrequencyTask = nil
        currentConnectionsStreamIntervalMilliseconds = nil
    }

    private func startPeriodicTask(
        intervalProvider: @escaping (AppState) -> UInt64,
        operation: @escaping (AppState) async -> Void) -> Task<Void, Never>
    {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await operation(self)
                do {
                    let interval = max(1_000_000_000, intervalProvider(self))
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    private func ensurePeriodicTasksForCurrentVisibility() {
        if isPanelPresented {
            if mediumFrequencyTask == nil {
                mediumFrequencyTask = self.startPeriodicTask(intervalProvider: { state in
                    state.mediumFrequencyIntervalNanoseconds
                }, operation: { state in
                    await state.refreshMediumFrequency()
                })
            }

            if lowFrequencyTask == nil {
                lowFrequencyTask = self.startPeriodicTask(intervalProvider: { state in
                    state.lowFrequencyIntervalNanoseconds
                }, operation: { state in
                    await state.refreshLowFrequency()
                })
            }
            return
        }

        mediumFrequencyTask?.cancel()
        lowFrequencyTask?.cancel()
        mediumFrequencyTask = nil
        lowFrequencyTask = nil
    }

    func refreshFromAPI(includeSlowCalls: Bool) async {
        await self.refreshHighFrequency()
        await self.refreshMediumFrequency()
        if includeSlowCalls {
            await self.refreshLowFrequency()
        }
    }

    private func refreshHighFrequency() async {
        self.updateDataAcquisitionPolicy()
    }

    func setPanelVisibility(_ presented: Bool) {
        guard isPanelPresented != presented else { return }
        isPanelPresented = presented
        if !presented {
            cancelProxyPortsAutoSave()
            self.clearTrafficPresentationHistory()
            self.releasePanelCachedData()
        }
        trimInMemoryLogsForCurrentVisibility()
        self.updateDataAcquisitionPolicy()

        guard presented else { return }
        self.flushPendingTrafficSnapshotIfNeeded(immediately: true)
        self.scheduleRefreshForActivatedTab(activeMenuTab)
        Task { [weak self] in
            await self?.refreshLatestAppRelease()
        }
    }

    func setActiveMenuTab(_ tab: RootTab) {
        let changed = activeMenuTab != tab
        activeMenuTab = tab
        self.updateDataAcquisitionPolicy()

        guard changed else { return }
        self.scheduleRefreshForActivatedTab(tab)
    }

    private func scheduleRefreshForActivatedTab(_ tab: RootTab) {
        activatedTabRefreshGeneration += 1
        let generation = activatedTabRefreshGeneration
        Task { [weak self] in
            guard let self else { return }
            await self.refreshForActivatedTab(tab, generation: generation)
        }
    }

    private func desiredDataAcquisitionPolicy(
        panelPresented: Bool,
        activeTab: RootTab) -> DataAcquisitionPolicy
    {
        let trafficEnabled = panelPresented || self.statusBarDisplayMode != .iconOnly

        if !panelPresented {
            return DataAcquisitionPolicy(
                enableTrafficStream: trafficEnabled,
                enableMemoryStream: false,
                enableConnectionsStream: false,
                connectionsIntervalMilliseconds: nil,
                enableLogsStream: false,
                mediumFrequencyIntervalNanoseconds: backgroundMediumFrequencyIntervalNanoseconds,
                lowFrequencyIntervalNanoseconds: backgroundLowFrequencyIntervalNanoseconds)
        }

        let lowFrequencyInterval: UInt64 = switch activeTab {
        case .proxy, .rules:
            foregroundLowFrequencyPrimaryTabsIntervalNanoseconds
        default:
            foregroundLowFrequencyOtherTabsIntervalNanoseconds
        }

        let memoryEnabled = activeTab == .proxy
        let connectionsEnabled = (activeTab == .proxy || activeTab == .activity)
        let logsEnabled = activeTab == .logs

        return DataAcquisitionPolicy(
            enableTrafficStream: trafficEnabled,
            enableMemoryStream: memoryEnabled,
            enableConnectionsStream: connectionsEnabled,
            connectionsIntervalMilliseconds: connectionsEnabled ? 1000 : nil,
            enableLogsStream: logsEnabled,
            mediumFrequencyIntervalNanoseconds: foregroundMediumFrequencyIntervalNanoseconds,
            lowFrequencyIntervalNanoseconds: lowFrequencyInterval)
    }

    func updateDataAcquisitionPolicy() {
        guard processManager.isRunning else {
            self.ensurePeriodicTasksForCurrentVisibility()
            mediumFrequencyIntervalNanoseconds = foregroundMediumFrequencyIntervalNanoseconds
            lowFrequencyIntervalNanoseconds = foregroundLowFrequencyPrimaryTabsIntervalNanoseconds
            return
        }

        let policy = self.desiredDataAcquisitionPolicy(
            panelPresented: isPanelPresented,
            activeTab: activeMenuTab)

        mediumFrequencyIntervalNanoseconds = policy.mediumFrequencyIntervalNanoseconds
        lowFrequencyIntervalNanoseconds = policy.lowFrequencyIntervalNanoseconds
        self.ensurePeriodicTasksForCurrentVisibility()
        self.applyStreamPolicy(policy)
    }

    func refreshForActivatedTab(_ tab: RootTab, generation: Int? = nil) async {
        guard processManager.isRunning else { return }

        func shouldContinueRefresh() -> Bool {
            guard let generation else { return true }
            return generation == activatedTabRefreshGeneration
        }

        guard shouldContinueRefresh() else { return }

        switch tab {
        case .proxy:
            await self.refreshMediumFrequency()
            guard shouldContinueRefresh() else { return }
            if proxyProvidersDetail.isEmpty || ruleItems.isEmpty {
                await refreshProvidersAndRules()
            }
        case .rules:
            await refreshProvidersAndRules()
        case .activity:
            await self.refreshConnections()
        case .logs:
            break
        case .system:
            await self.refreshMediumFrequency()
            guard shouldContinueRefresh() else { return }
            await self.refreshSystemProxyStatus()
        }
    }

    private func refreshMediumFrequency() async {
        guard isPanelPresented else { return }
        await runRefresh {
            let client = try self.clientOrThrow()
            if self.activeMenuTab == .proxy {
                async let versionTask: VersionInfo = client.request(.version)
                async let configTask: ConfigSnapshot = client.request(.getConfigs)
                async let proxyGroupsTask = self.fetchProxyGroupsAndProviders(using: client)

                let (version, config, proxyGroupsPayload) = try await (
                    versionTask,
                    configTask,
                    proxyGroupsTask)
                self.version = version.version
                self.applyRuntimeConfigSnapshot(config)
                self.applyProxyGroupsResponse(
                    proxyGroupsPayload.groups,
                    proxyProviders: proxyGroupsPayload.providers)
            } else {
                async let versionTask: VersionInfo = client.request(.version)
                async let configTask: ConfigSnapshot = client.request(.getConfigs)

                let (version, config) = try await (versionTask, configTask)
                self.version = version.version
                self.applyRuntimeConfigSnapshot(config)
            }
        }
    }

    func fetchRuntimeConfigSnapshot() async throws -> ConfigSnapshot {
        let client = try clientOrThrow()
        let config: ConfigSnapshot = try await client.request(.getConfigs)
        self.applyRuntimeConfigSnapshot(config)
        return config
    }

    private func applyRuntimeConfigSnapshot(_ config: ConfigSnapshot) {
        let remoteMode = normalizeMode(config.mode)
        if let remoteMode {
            currentMode = remoteMode
        }
        logLevel = config.logLevel ?? logLevel

        port = config.port
        socksPort = config.socksPort
        redirPort = config.redirPort
        tproxyPort = config.tproxyPort
        mixedPort = config.mixedPort ?? 0

        if let externalController = config.externalController {
            applyExternalControllerFromConfig(externalController)
        }
        syncEditableSettings(from: config)
    }

    func resetTrafficPresentation() {
        traffic = TrafficSnapshot(up: 0, down: 0)
        self.clearTrafficPresentationHistory()
    }

    func clearTrafficPresentationHistory() {
        displayUpTotal = 0
        displayDownTotal = 0
        trafficHistoryUp = []
        trafficHistoryDown = []
        trafficHistoryUp.reserveCapacity(historyMaxPoints)
        trafficHistoryDown.reserveCapacity(historyMaxPoints)
        lastTrafficSampleAt = nil
    }

    private func releasePanelCachedData() {
        connectionsCount = 0
        connections.removeAll(keepingCapacity: false)

        memory = MemorySnapshot(inuse: 0)

        proxyGroups.removeAll(keepingCapacity: false)
        groupLatencyLoading.removeAll(keepingCapacity: false)
        groupLatencies.removeAll(keepingCapacity: false)
        proxyHistoryLatestDelay.removeAll(keepingCapacity: false)

        providerProxyCount = 0
        providerRuleCount = 0
        rulesCount = 0
        proxyProvidersDetail.removeAll(keepingCapacity: false)
        providerUpdating.removeAll(keepingCapacity: false)
        ruleProviders.removeAll(keepingCapacity: false)
        ruleItems.removeAll(keepingCapacity: false)
    }

    func appendTrafficHistory(up: Int64, down: Int64) {
        trafficHistoryUp.append(max(0, up))
        trafficHistoryDown.append(max(0, down))

        if trafficHistoryUp.count > historyMaxPoints {
            trafficHistoryUp.removeFirst(trafficHistoryUp.count - historyMaxPoints)
        }
        if trafficHistoryDown.count > historyMaxPoints {
            trafficHistoryDown.removeFirst(trafficHistoryDown.count - historyMaxPoints)
        }
    }

    func updateTrafficTotals(from snapshot: TrafficSnapshot) {
        if let upTotal = snapshot.upTotal, let downTotal = snapshot.downTotal {
            displayUpTotal = max(0, upTotal)
            displayDownTotal = max(0, downTotal)
            lastTrafficSampleAt = Date()
            return
        }

        let now = Date()
        if let last = lastTrafficSampleAt {
            let delta = max(0, now.timeIntervalSince(last))
            displayUpTotal += Int64(Double(max(0, snapshot.up)) * delta)
            displayDownTotal += Int64(Double(max(0, snapshot.down)) * delta)
        }
        lastTrafficSampleAt = now
    }

    private func refreshLowFrequency() async {
        guard isPanelPresented else { return }
        switch activeMenuTab {
        case .proxy:
            await refreshProvidersAndRules()
            await self.refreshSystemProxyStatus()
        case .rules:
            await refreshProvidersAndRules()
        case .system:
            await self.refreshSystemProxyStatus()
        case .activity, .logs:
            break
        }
    }

    func refreshProxyGroups() async {
        await runRefresh {
            let client = try self.clientOrThrow()
            let payload = try await self.fetchProxyGroupsAndProviders(using: client)
            self.applyProxyGroupsResponse(payload.groups, proxyProviders: payload.providers)
        }
    }

    private func fetchProxyGroupsAndProviders(using client: MihomoAPIClient) async throws -> (
        groups: ProxyGroupsResponse,
        providers: [String: ProviderDetail])
    {
        async let groupsTask: ProxyGroupsResponse = client.request(.proxies)
        async let proxyProvidersTask: ProviderSummary? = try? await client.request(.proxyProviders)
        let (groupsResponse, proxyProviders) = try await (groupsTask, proxyProvidersTask)
        return (groupsResponse, proxyProviders?.providers ?? [:])
    }

    private func applyProxyGroupsResponse(
        _ response: ProxyGroupsResponse,
        proxyProviders: [String: ProviderDetail] = [:])
    {
        let providerLookup = proxyProviders.isEmpty ? proxyProvidersDetail : proxyProviders
        let proxiesWithHealthcheckConfig = response.proxies.values.map { proxy in
            let provider = providerLookup[proxy.name]
            let resolvedTestURL = self.normalizedHealthcheckURL(proxy.testUrl)
                ?? self.normalizedHealthcheckURL(provider?.testUrl)
            let resolvedTimeout = self.normalizedHealthcheckTimeout(proxy.timeout)
                ?? self.normalizedHealthcheckTimeout(provider?.timeout)

            return ProxyGroup(
                name: proxy.name,
                type: proxy.type,
                now: proxy.now,
                all: proxy.all,
                testUrl: resolvedTestURL,
                timeout: resolvedTimeout,
                icon: proxy.icon,
                hidden: proxy.hidden,
                latestDelay: proxy.latestDelay)
        }

        let sortIndex = (response.proxies["GLOBAL"]?.all ?? []) + ["GLOBAL"]
        var sortIndexMap: [String: Int] = [:]
        for (index, name) in sortIndex.enumerated() where sortIndexMap[name] == nil {
            sortIndexMap[name] = index
        }

        proxyGroups = proxiesWithHealthcheckConfig
            .enumerated()
            .filter {
                !$0.element.all.isEmpty
            }
            .sorted { lhs, rhs in
                let lhsOrder = sortIndexMap[lhs.element.name] ?? -1
                let rhsOrder = sortIndexMap[rhs.element.name] ?? -1

                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var historyMap: [String: Int] = [:]
        for proxy in response.proxies.values {
            if let latest = proxy.latestDelay {
                historyMap[proxy.name] = latest
            }
        }
        proxyHistoryLatestDelay = historyMap
    }

    func normalizedHealthcheckURL(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func normalizedHealthcheckTimeout(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    func refreshConnections() async {
        let policy = self.desiredDataAcquisitionPolicy(panelPresented: isPanelPresented, activeTab: activeMenuTab)
        guard policy.enableConnectionsStream else {
            cancelStream(.connections)
            return
        }
        startConnectionsStream(intervalMilliseconds: policy.connectionsIntervalMilliseconds)
    }

    func refreshSystemProxyStatus() async {
        do {
            isSystemProxyEnabled = try await readSystemProxyEnabledState()
        } catch {
            appendLog(level: "error", message: tr("log.system_proxy.read_failed", systemProxyErrorMessage(error)))
        }
    }

    private func applyStreamPolicy(_ policy: DataAcquisitionPolicy) {
        self.syncStream(.traffic, enabled: policy.enableTrafficStream) { startTrafficStream() }
        self.syncStream(.memory, enabled: policy.enableMemoryStream) { startMemoryStream() }
        self.syncConnectionsStream(
            enabled: policy.enableConnectionsStream,
            intervalMilliseconds: policy.connectionsIntervalMilliseconds)
        self.syncStream(.logs, enabled: policy.enableLogsStream) { startLogsStream() }
    }

    private func syncConnectionsStream(enabled: Bool, intervalMilliseconds: Int?) {
        self.syncStream(
            .connections,
            enabled: enabled,
            forceRestart: currentConnectionsStreamIntervalMilliseconds != intervalMilliseconds)
        {
            startConnectionsStream(intervalMilliseconds: intervalMilliseconds)
        }
    }

    private func syncStream(
        _ kind: StreamKind,
        enabled: Bool,
        forceRestart: Bool = false,
        start: () -> Void)
    {
        guard enabled else {
            cancelStream(kind)
            return
        }
        guard forceRestart || webSocketTask(for: kind) == nil else { return }
        start()
    }
}
