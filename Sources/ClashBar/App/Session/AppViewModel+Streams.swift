import Foundation
import MihomoKit

@MainActor
extension AppViewModel {
    enum StreamKind: CaseIterable, Hashable {
        case traffic
        case memory
        case connections
        case logs

        var key: String {
            switch self {
            case .traffic: "traffic"
            case .memory: "memory"
            case .connections: "connections"
            case .logs: "logs"
            }
        }

        var label: String {
            switch self {
            case .traffic: "app.stream.label.traffic"
            case .memory: "app.stream.label.memory"
            case .connections: "app.stream.label.connections"
            case .logs: "app.stream.label.logs"
            }
        }
    }

    func configureStreamCoordinator() {
        self.streams.shouldReconnect = { [weak self] in
            guard let self else { return false }
            if self.networkReachabilityStatus == .offline {
                return false
            }
            return self.isRemoteTarget || self.processManager.isRunning
        }
        self.streams.onDisconnect = { [weak self] key, message in
            guard let self else { return }
            let label = StreamKind.allCases.first(where: { $0.key == key })?.label ?? key
            self.appendLog(
                level: "error", message: tr("log.stream.disconnected", tr(label), message))
        }
        self.streams.onStartError = { [weak self] key, error in
            guard let self else { return }
            let label = StreamKind.allCases.first(where: { $0.key == key })?.label ?? key
            self.appendLog(
                level: "error",
                message: tr("log.stream.start_failed", tr(label), error.localizedDescription))
        }
        self.streams.onMediumFrequencyPoll = { [weak self] in
            await self?.refreshMediumFrequency()
        }
        self.streams.onLowFrequencyPoll = { [weak self] in
            await self?.refreshLowFrequency()
        }
    }

    func startPolling() {
        self.cancelPolling()
        self.updateDataAcquisitionPolicy()
    }

    func pauseHighFrequencyStreams() {
        self.streams.pauseHighFrequencyStreams()
        self.cancelStream(.connections)
        self.cancelStream(.logs)
        self.cancelStream(.memory)
    }

    func resumeHighFrequencyStreams() {
        self.updateDataAcquisitionPolicy()
    }

    func cancelPolling() {
        self.streams.cancelPolling()
        self.streams.cancelAll()
        for kind in StreamKind.allCases {
            self.cancelStream(kind)
        }
    }

    func refreshFromAPI(includeSlowCalls: Bool) async {
        self.updateDataAcquisitionPolicy()
        await self.refreshMediumFrequency()
        if includeSlowCalls {
            await self.refreshLowFrequency()
        }
    }

    func setPanelVisibility(_ presented: Bool) {
        guard isPanelPresented != presented else { return }
        isPanelPresented = presented
        if !presented {
            self.settingsStore.cancelProxyPortsAutoSave()
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

    func updateDataAcquisitionPolicy() {
        let isRunning = self.isRemoteTarget || self.processManager.isRunning
        guard isRunning else {
            self.cancelPolling()
            return
        }

        let panelPresented = self.isPanelPresented
        let activeTab = self.activeMenuTab

        self.streams.updatePollingSchedule(
            isRunning: isRunning,
            isPanelPresented: panelPresented,
            isHighFrequencyTabActive: activeTab == .proxy || activeTab == .rules)

        let enableTraffic = panelPresented || self.statusBarDisplayMode != .iconOnly
        let enableMemory = panelPresented && activeTab == .proxy
        let enableConnections = panelPresented && (activeTab == .proxy || activeTab == .connections)
        let enableLogs = panelPresented && activeTab == .logs

        self.syncStream(.traffic, enabled: enableTraffic) { self.startTrafficStream() }
        self.syncStream(.memory, enabled: enableMemory) { self.startMemoryStream() }
        self.syncConnectionsStream(enabled: enableConnections, intervalMilliseconds: enableConnections ? 1000 : nil)
        self.syncStream(
            .logs,
            enabled: enableLogs,
            forceRestart: self.currentLogsStreamLevel != self.logsStreamLevelFilter())
        {
            self.startLogsStream()
        }
    }

    func refreshForActivatedTab(_ tab: RootTab, generation: Int? = nil) async {
        guard self.isRemoteTarget || self.processManager.isRunning else { return }

        func shouldContinueRefresh() -> Bool {
            guard let generation else { return true }
            return generation == activatedTabRefreshGeneration
        }

        guard shouldContinueRefresh() else { return }

        switch tab {
        case .proxy:
            await self.refreshMediumFrequency()
            guard shouldContinueRefresh() else { return }
            if self.proxyStore.proxyProvidersDetail.isEmpty || self.rulesStore.rulesCount == 0 {
                await refreshProvidersAndRules()
            }
        case .rules:
            await refreshProvidersAndRules()
        case .connections:
            await self.refreshConnections()
        case .logs:
            break
        case .system:
            await self.refreshMediumFrequency()
            guard shouldContinueRefresh() else { return }
            if !self.isRemoteTarget, self.proxyStore.hasSystemProxyOpenIntent {
                await self.proxyStore.refreshSystemProxyStatus()
            }
        }
    }

    private func refreshMediumFrequency() async {
        guard isPanelPresented else { return }
        await runRefresh {
            let client = try self.clientOrThrow()
            let needsVersion = self.version == "-" || self.version.isEmpty
            let snapshot = try await client
                .fetchMediumFrequencySnapshot(
                    includeProxyGroups: self.activeMenuTab == .proxy,
                    includeVersion: needsVersion)

            if let version = snapshot.versionInfo?.version {
                self.version = version
            }
            self.applyRuntimeConfigSnapshot(snapshot.configSnapshot)

            if let proxyGroupsPayload = snapshot.proxyGroupsPayload {
                self.noteProxyProvidersAPIAvailability(error: proxyGroupsPayload.providersError)
                self.applyProxyGroupsResponse(
                    proxyGroupsPayload.groups,
                    proxyProviders: proxyGroupsPayload.providers)
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
            self.settingsStore.editableSettings.mode = remoteMode
        }
        logLevel = config.logLevel ?? logLevel

        port = config.port
        socksPort = config.socksPort
        redirPort = config.redirPort
        tproxyPort = config.tproxyPort
        mixedPort = config.mixedPort ?? 0

        if !self.isRemoteTarget, let externalController = config.externalController {
            applyExternalControllerFromConfig(externalController)
        }
        if self.isRemoteTarget || config.externalUIURL != nil || config.externalUIName != nil {
            self.applyExternalUIConfiguration(
                hasURL: config.externalUIURL.trimmedNonEmpty != nil,
                name: config.externalUIName)
        }
        self.settingsStore.syncEditableSettings(from: config)
        self.refreshLogsStreamLevelIfNeeded()
    }

    func resetTrafficPresentation() {
        self.trafficStore.resetPresentation()
        self.lastTrafficSampleAt = nil
    }

    func clearProxyPresentation() {
        self.proxyStore.resetPresentation()
    }

    func clearTrafficPresentationHistory() {
        self.trafficStore.resetHistory(maxPoints: historyMaxPoints)
        lastTrafficSampleAt = nil
    }

    private func releasePanelCachedData() {
        self.connectionsStore.reset()

        self.trafficStore.memory = MemorySnapshot(inuse: 0)

        self.proxyStore.groupLatencyLoading.removeAll(keepingCapacity: false)
        self.proxyStore.proxyLatencyTesting.removeAll(keepingCapacity: false)

        self.rulesStore.reset()
    }

    func appendTrafficHistory(up: Int64, down: Int64) {
        self.trafficStore.appendTrafficHistory(up: up, down: down)
    }

    func updateTrafficTotals(from snapshot: TrafficSnapshot) {
        self.trafficStore.updateTrafficTotals(from: snapshot)
    }

    private func refreshLowFrequency() async {
        guard isPanelPresented else { return }
        switch activeMenuTab {
        case .proxy:
            await refreshProvidersAndRules()
            if !self.isRemoteTarget {
                await self.proxyStore.refreshSystemProxyStatus()
            }
        case .rules:
            await refreshProvidersAndRules()
        case .system:
            if !self.isRemoteTarget {
                await self.proxyStore.refreshSystemProxyStatus()
            }
        case .connections, .logs:
            break
        }
    }

    func refreshProxyGroups() async {
        await runRefresh {
            let client = try self.clientOrThrow()
            let payload = try await client.fetchProxyGroupsAndProviders()
            self.noteProxyProvidersAPIAvailability(error: payload.providersError)
            self.applyProxyGroupsResponse(payload.groups, proxyProviders: payload.providers)
        }
    }

    private func noteProxyProvidersAPIAvailability(error: Error?) {
        if let error {
            guard !self.proxyProvidersAPIUnavailableLogged else { return }
            self.proxyProvidersAPIUnavailableLogged = true
            self.appendLog(
                level: "info",
                message: tr("log.providers.api_unavailable", error.localizedDescription))
        } else if self.proxyProvidersAPIUnavailableLogged {
            self.proxyProvidersAPIUnavailableLogged = false
        }
    }

    private func applyProxyGroupsResponse(
        _ response: ProxyGroupsResponse,
        proxyProviders: [String: ProviderDetail] = [:])
    {
        let providerLookup = proxyProviders.isEmpty ? self.proxyStore.proxyProvidersDetail : proxyProviders
        let proxiesWithHealthcheckConfig = response.proxies.values.map { proxy in
            let provider = providerLookup[proxy.name]
            let resolvedTestURL = proxy.testUrl?.trimmedNonEmpty ?? provider?.testUrl?.trimmedNonEmpty
            let resolvedTimeout = proxy.timeout.flatMap { $0 > 0 ? $0 : nil }
                ?? provider?.timeout.flatMap { $0 > 0 ? $0 : nil }

            return ProxyGroup(
                name: proxy.name,
                type: proxy.type,
                now: proxy.now,
                all: proxy.all,
                testUrl: resolvedTestURL,
                timeout: resolvedTimeout,
                icon: proxy.icon,
                hidden: proxy.hidden,
                delayHistory: proxy.delayHistory)
        }

        let sortIndex = (response.proxies["GLOBAL"]?.all ?? []) + ["GLOBAL"]
        var sortIndexMap: [String: Int] = [:]
        for (index, name) in sortIndex.enumerated() where sortIndexMap[name] == nil {
            sortIndexMap[name] = index
        }

        self.proxyStore.proxyGroups = proxiesWithHealthcheckConfig
            .filter { !$0.all.isEmpty }
            .sorted { lhs, rhs in
                let lhsOrder = sortIndexMap[lhs.name] ?? .max
                let rhsOrder = sortIndexMap[rhs.name] ?? .max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        var delaySamples: [String: [Int]] = [:]
        var nodeTypes: [String: String] = [:]
        for proxy in response.proxies.values {
            if proxy.all.isEmpty, let type = proxy.type.trimmedNonEmpty {
                nodeTypes[proxy.name] = type
            }
            if !proxy.delayHistory.isEmpty {
                delaySamples[proxy.name] = proxy.delayHistory
            }
        }

        for provider in providerLookup.values {
            for node in provider.proxies ?? [] {
                if !node.delayHistory.isEmpty, delaySamples[node.name] == nil {
                    delaySamples[node.name] = node.delayHistory
                }
                if let type = node.type.trimmedNonEmpty, nodeTypes[node.name] == nil {
                    nodeTypes[node.name] = type
                }
            }
        }

        self.proxyStore.proxyDelaySamples = ProxyDelayHistory.merge(
            api: delaySamples,
            previous: self.proxyStore.proxyDelaySamples)
        self.proxyStore.proxyNodeTypes = nodeTypes
    }

    func refreshConnections() async {
        let enableConnections = self
            .isPanelPresented && (self.activeMenuTab == .proxy || self.activeMenuTab == .connections)
        guard enableConnections else {
            self.cancelStream(.connections)
            return
        }
        self.startConnectionsStream(intervalMilliseconds: 1000)
    }

    private func syncConnectionsStream(enabled: Bool, intervalMilliseconds: Int?) {
        self.syncStream(
            .connections,
            enabled: enabled,
            forceRestart: currentConnectionsStreamIntervalMilliseconds != intervalMilliseconds)
        {
            self.startConnectionsStream(intervalMilliseconds: intervalMilliseconds)
        }
    }

    private func syncStream(
        _ kind: StreamKind,
        enabled: Bool,
        forceRestart: Bool = false,
        start: () -> Void)
    {
        guard enabled else {
            self.cancelStream(kind)
            return
        }
        guard forceRestart || self.webSocketTask(for: kind) == nil else { return }
        start()
    }

    func startStream(
        kind: StreamKind,
        preserveReconnectState: Bool = false,
        makeWebSocket: @escaping (MihomoAPIService) throws -> URLSessionWebSocketTask,
        onPayload: @escaping (Data) -> Void)
    {
        if kind == .connections {
            currentConnectionsStreamIntervalMilliseconds = nil
        }
        if kind == .logs {
            currentLogsStreamLevel = nil
        }
        if kind == .traffic {
            self.resetPendingTrafficSnapshotState()
        }

        if !preserveReconnectState {
            self.streams.clearReconnectState(for: kind.key)
        }

        self.streams.start(
            key: kind.key,
            makeWebSocket: { [weak self] in
                guard let self else { throw CancellationError() }
                let client = try self.clientOrThrow()
                return try makeWebSocket(client)
            },
            onPayload: onPayload,
            normalizePayload: Self.normalizeWebSocketPayload)
    }

    private static func normalizeWebSocketPayload(_ message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case let .data(data):
            return data.isEmpty ? nil : data
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "null", trimmed != "{}" else { return nil }
            return Data(trimmed.utf8)
        @unknown default:
            return nil
        }
    }

    func cancelStream(_ kind: StreamKind, resetReconnectState: Bool = true) {
        self.streams.cancel(key: kind.key, resetReconnectState: resetReconnectState)
        if kind == .connections {
            currentConnectionsStreamIntervalMilliseconds = nil
        }
        if kind == .logs {
            currentLogsStreamLevel = nil
        }
        if kind == .traffic {
            self.resetPendingTrafficSnapshotState()
        }
    }

    func webSocketTask(for kind: StreamKind) -> URLSessionWebSocketTask? {
        self.streams.webSocketTask(for: kind.key)
    }

    func startTrafficStream() {
        self.startStream(
            kind: .traffic,
            makeWebSocket: { try $0.makeWebSocketTask(for: .traffic) },
            onPayload: { [weak self] payload in
                guard let self else { return }
                self.pendingTrafficPayload = payload
                self.flushPendingTrafficSnapshotIfNeeded()
            })
    }

    func flushPendingTrafficSnapshotIfNeeded(immediately: Bool = false) {
        guard self.pendingTrafficPayload != nil else { return }
        if immediately {
            self.publishPendingTrafficSnapshot()
            return
        }
        self.schedulePendingTrafficSnapshotPublishIfNeeded()
    }

    func startMemoryStream() {
        self.startDecodableStream(
            kind: .memory,
            makeWebSocket: { try $0.makeWebSocketTask(for: .memory) },
            onDecoded: { [weak self] (snapshot: MemorySnapshot) in
                guard let self else { return }
                self.trafficStore.applyMemorySnapshot(snapshot)
            })
    }

    func startConnectionsStream(intervalMilliseconds: Int? = nil) {
        self.startDecodableStream(
            kind: .connections,
            makeWebSocket: {
                try $0.makeWebSocketTask(for: .connections(interval: intervalMilliseconds))
            },
            onDecoded: { [weak self] (snapshot: ConnectionsSnapshot) in
                guard let self else { return }
                self.applyConnectionsSnapshot(snapshot)
            })
        currentConnectionsStreamIntervalMilliseconds = intervalMilliseconds
    }

    func startLogsStream() {
        let level = self.logsStreamLevelFilter()
        self.startStream(
            kind: .logs,
            makeWebSocket: { try $0.makeWebSocketTask(for: .logs(level: level)) },
            onPayload: { [weak self] payload in
                guard let self else { return }
                if let line = self.decodeStreamLogPayload(payload: payload) {
                    self.logsStore.handleLogLine(LogLine(type: line.level, payload: line.message))
                }
            })
        currentLogsStreamLevel = level
    }

    private func decodeStreamLogPayload(payload: Data) -> (level: String, message: String)? {
        if let log = try? self.streamJSONDecoder.decode(LogLine.self, from: payload) {
            let level = (log.type?.isEmpty == false) ? (log.type ?? "info") : "info"
            let message = log.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return (level: level, message: message)
            }
        }

        if let response = try? self.streamJSONDecoder.decode(LogsResponse.self, from: payload),
           let first = response.logs?.first
        {
            let level = (first.type?.isEmpty == false) ? (first.type ?? "info") : "info"
            let message = first.payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return (level: level, message: message)
            }
        }

        if let text = String(data: payload, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return (level: "info", message: text)
        }

        return nil
    }

    func logsStreamLevelFilter() -> String? {
        let runtimeLevel = self.logLevel.trimmed.lowercased()
        if ConfigLogLevel(rawValue: runtimeLevel) != nil {
            return runtimeLevel
        }

        let level = self.settingsStore.editableSettings.logLevel.trimmed.lowercased()
        guard ConfigLogLevel(rawValue: level) != nil else { return nil }
        return level
    }

    func refreshLogsStreamLevelIfNeeded() {
        guard self.webSocketTask(for: .logs) != nil else { return }
        guard currentLogsStreamLevel != self.logsStreamLevelFilter() else { return }
        self.startLogsStream()
    }

    private func schedulePendingTrafficSnapshotPublishIfNeeded() {
        guard self.trafficDecodeTask == nil else { return }

        let elapsed = Date().timeIntervalSince(self.lastTrafficDecodeAt)
        let publishInterval = Double(self.trafficPublishIntervalNanoseconds) / 1_000_000_000
        if elapsed >= publishInterval {
            self.publishPendingTrafficSnapshot()
            return
        }

        let remainingDelay = max(0.01, publishInterval - elapsed)
        let remainingNanoseconds = UInt64(remainingDelay * 1_000_000_000)
        self.trafficDecodeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: remainingNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.publishPendingTrafficSnapshot()
        }
    }

    private func publishPendingTrafficSnapshot() {
        self.trafficDecodeTask?.cancel()
        self.trafficDecodeTask = nil

        guard let payload = self.pendingTrafficPayload else { return }
        self.pendingTrafficPayload = nil

        guard let snapshot = try? self.streamJSONDecoder.decode(TrafficSnapshot.self, from: payload)
        else {
            return
        }
        self.lastTrafficDecodeAt = Date()
        self.applyTrafficSnapshot(snapshot)

        if self.pendingTrafficPayload != nil {
            self.schedulePendingTrafficSnapshotPublishIfNeeded()
        }
    }

    private func applyTrafficSnapshot(_ snapshot: TrafficSnapshot) {
        self.trafficStore.applyTrafficSnapshot(snapshot, isPanelPresented: self.isPanelPresented)
    }

    private func resetPendingTrafficSnapshotState() {
        self.trafficDecodeTask?.cancel()
        self.trafficDecodeTask = nil
        self.pendingTrafficPayload = nil
        self.lastTrafficDecodeAt = .distantPast
    }

    private func applyConnectionsSnapshot(_ snapshot: ConnectionsSnapshot) {
        self.connectionsStore.applySnapshot(snapshot)
    }

    func startDecodableStream<Payload: Decodable>(
        kind: StreamKind,
        makeWebSocket: @escaping (MihomoAPIService) throws -> URLSessionWebSocketTask,
        onDecoded: @escaping (Payload) -> Void)
    {
        self.startStream(
            kind: kind,
            makeWebSocket: makeWebSocket,
            onPayload: { [weak self] payload in
                guard let self else { return }
                guard let decoded = try? self.streamJSONDecoder.decode(Payload.self, from: payload)
                else {
                    return
                }
                onDecoded(decoded)
            })
    }
}

extension AppViewModel {
    func runRefresh(_ block: () async throws -> Void) async {
        do {
            self.ensureAPIClient()
            try await block()
            if self.apiStatus != .healthy {
                self.apiStatus = .healthy
            }
            self.lastAPIRefreshErrorFingerprint = nil
        } catch {
            if self.apiStatus != .degraded {
                self.apiStatus = .degraded
            }
            let fingerprint = "\(String(reflecting: type(of: error))):\(error.localizedDescription)"
            guard self.lastAPIRefreshErrorFingerprint != fingerprint else { return }
            self.lastAPIRefreshErrorFingerprint = fingerprint
            self.appendLog(level: "error", message: error.localizedDescription)
        }
    }

    func runNoResponseAction(_ name: String, operation: () async throws -> Void) async {
        do {
            ensureAPIClient()
            try await operation()
            appendLog(level: "info", message: tr("log.action.success", name))
        } catch {
            appendLog(level: "error", message: tr("log.action.failed", name, error.localizedDescription))
        }
    }
}
