import AppKit
import Foundation
import MihomoKit

@MainActor
extension AppViewModel {
    private enum CoreTransitionKind {
        case stop
        case restart
    }

    func startCore(trigger: StartTrigger = .manual) async {
        guard !self.isRemoteTarget else { return }
        guard !isCoreActionProcessing else { return }
        if trigger == .manual {
            shouldResumeCoreAfterNetworkRecovery = false
        }
        coreActionState = .starting
        defer { coreActionState = .idle }
        var settingsOverlay = self.settingsStore.editableSettings
        settingsOverlay = self.overlayApplyingPendingCoreFeatureRecovery(settingsOverlay)
        self.settingsStore.preserveLocalSettingsOnNextSync = true
        do {
            guard let configPath = await resolveSelectedConfigPath() else {
                let message = tr("log.start.no_config")
                self.reportCoreStartFailure(message: message, trigger: trigger, markFailedOnManual: false)
                return
            }

            settingsOverlay = try await self.proxyStore.prepareTunOverlayForCoreStartup(settingsOverlay)

            guard await self.validateConfigBeforeCoreLaunch(configPath: configPath) else {
                self.settingsStore.preserveLocalSettingsOnNextSync = false
                if trigger == .auto {
                    let fileName = URL(fileURLWithPath: configPath).lastPathComponent
                    self.startupErrorMessage = tr("app.config.validation_failed.startup", fileName)
                    statusText = "Stopped"
                    apiStatus = .unknown
                } else {
                    statusText = "Failed"
                    apiStatus = .failed
                }
                return
            }

            let launchController = applyExternalControllerFromSelectedConfigFile(configPath: configPath)
            statusText = "Starting"
            _ = try await self.processManager.startAsync(configPath: configPath, controller: launchController)

            await self.completeCoreBootstrap(
                configPath: configPath,
                settingsOverlay: settingsOverlay,
                isRestart: false,
                providerTrigger: .start)
        } catch {
            self.settingsStore.preserveLocalSettingsOnNextSync = false
            let message = tr("log.start.failed", self.coreErrorMessage(error))
            self.reportCoreStartFailure(message: message, trigger: trigger, markFailedOnManual: true)
        }
    }

    private func reportCoreStartFailure(message: String, trigger: StartTrigger, markFailedOnManual: Bool) {
        self.appendLog(level: "error", message: message)
        self.presentCoreFailureAlert(
            title: self.tr("app.core.alert.start_failed.title"),
            message: message,
            dedupeKey: "core-start-failed")
        if trigger == .auto {
            self.startupErrorMessage = message
            self.statusText = "Stopped"
            self.apiStatus = .unknown
        } else if markFailedOnManual {
            self.statusText = "Failed"
            self.apiStatus = .failed
        }
    }

    func stopCore(trigger: StopTrigger = .manual) async {
        guard !self.isRemoteTarget else { return }
        guard !isCoreActionProcessing else { return }
        if trigger == .manual {
            shouldResumeCoreAfterNetworkRecovery = false
        }
        let recoverySnapshotBeforeStop = self.currentCoreFeatureRecoverySnapshot()
        coreActionState = .stopping
        defer { coreActionState = .idle }
        await self.prepareCoreFeatureRecoveryBeforeCoreTransition(
            fallbackRecovery: recoverySnapshotBeforeStop,
            transitionKind: .stop,
            disableRuntimeTunBeforeStop: trigger == .networkLoss)
        self.proxyStore.cancelProviderRefresh(reason: "stop requested")
        await self.processManager.stopAsync()
        cancelPolling()
        statusText = "Stopped"
        apiStatus = .unknown
        version = "-"
        clearProxyPresentation()
        resetTrafficPresentation()
    }

    func restartCore(trigger: ProviderRefreshTrigger = .restart) async {
        guard !self.isRemoteTarget else { return }
        guard !isCoreActionProcessing else { return }
        coreActionState = .restarting
        defer { coreActionState = .idle }
        self.settingsStore.preserveLocalSettingsOnNextSync = true
        self.proxyStore.cancelProviderRefresh(reason: "restart requested")
        do {
            guard let configPath = await resolveSelectedConfigPath() else {
                self.reportCoreRestartFailure(message: tr("log.start.no_config"))
                return
            }

            guard await self.validateConfigBeforeCoreLaunch(configPath: configPath) else {
                self.settingsStore.preserveLocalSettingsOnNextSync = false
                return
            }

            let launchController = applyExternalControllerFromSelectedConfigFile(configPath: configPath)
            let recoverySnapshotBeforeRestart = self.currentCoreFeatureRecoverySnapshot()
            await self.prepareCoreFeatureRecoveryBeforeCoreTransition(
                fallbackRecovery: recoverySnapshotBeforeRestart,
                transitionKind: .restart,
                disableRuntimeTunBeforeStop: false)
            let settingsOverlay = self.overlayApplyingPendingCoreFeatureRecovery(self.settingsStore.editableSettings)
            _ = try await self.processManager.restartAsync(configPath: configPath, controller: launchController)
            await self.completeCoreBootstrap(
                configPath: configPath,
                settingsOverlay: settingsOverlay,
                isRestart: true,
                providerTrigger: trigger)
        } catch {
            self.settingsStore.preserveLocalSettingsOnNextSync = false
            self.reportCoreRestartFailure(message: tr("log.restart.failed", self.coreErrorMessage(error)))
        }
    }

    private func reportCoreRestartFailure(message: String) {
        self.appendLog(level: "error", message: message)
        self.presentCoreFailureAlert(
            title: self.tr("app.core.alert.restart_failed.title"),
            message: message,
            dedupeKey: "core-restart-failed")
    }

    func performPrimaryCoreAction() async {
        guard !isCoreActionProcessing else { return }
        if isRuntimeRunning {
            await self.restartCore()
        } else {
            await self.startCore(trigger: .manual)
        }
    }

    func setUILanguage(_ language: AppLanguage) {
        guard uiLanguage != language else { return }
        uiLanguage = language
        defaults.set(language.rawValue, forKey: uiLanguageKey)
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        guard appearanceMode != mode else { return }
        appearanceMode = mode
        defaults.set(mode.rawValue, forKey: appearanceModeKey)
        self.applyAppAppearance()
    }

    func quitApp() async {
        self.prepareForTermination()
        self.isPanelPresented = false
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }
        NSApplication.shared.terminate(nil)
    }

    func shutdownForTermination() {
        self.prepareForTermination()
        self.systemProxyService.clearBlocking(timeout: 2.0)
        if processManager.isRunning {
            self.processManager.stop()
        }
    }

    func cancelOwnedTasks() {
        self.shouldResumeCoreAfterNetworkRecovery = false
        self.stopNetworkReachabilityMonitoring()
        self.stopConfigDirectoryMonitoring()
        self.proxyStore.cancelProviderRefresh(reason: "quit requested")
        self.cancelPolling()
        self.remoteMachineStore.stopPeriodicConnectivityChecks()
        self.ssidMonitorService.stop()
        self.trafficDecodeTask?.cancel()
        self.trafficDecodeTask = nil
        self.startupRefreshTask?.cancel()
        self.startupRefreshTask = nil
        self.autoStartTask?.cancel()
        self.autoStartTask = nil
        self.coreUpgradeFeedbackClearTask?.cancel()
        self.coreUpgradeFeedbackClearTask = nil
        self.geoUpdateFeedbackClearTask?.cancel()
        self.geoUpdateFeedbackClearTask = nil
    }

    private func prepareForTermination() {
        self.defaults.set(self.proxyStore.isSystemProxyEnabled, forKey: self.systemProxyEnabledOnQuitKey)
        self.cancelOwnedTasks()
        self.flushPendingMihomoLogsIfNeeded()
        Task { [clashbarLogStore, mihomoLogStore] in
            await clashbarLogStore.flush()
            await mihomoLogStore.flush()
        }
    }

    func applyAppAppearance() {
        let app = NSApplication.shared
        switch appearanceMode {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func normalizeMode(_ raw: String?) -> CoreMode? {
        guard let raw else { return nil }
        return CoreMode(rawValue: raw.lowercased())
    }

    @discardableResult
    func validateConfigBeforeCoreLaunch(configPath: String) async -> Bool {
        guard let details = await self.configValidationFailureDetails(configPath: configPath) else {
            return true
        }

        self.handleConfigValidationFailure(configPath: configPath, details: details)
        return false
    }

    func configValidationFailureDetails(configPath: String) async -> String? {
        do {
            try await self.processManager.validateConfigAsync(configPath: configPath)
            return nil
        } catch {
            let detailsRaw = self.coreErrorMessage(error).trimmingCharacters(in: .whitespacesAndNewlines)
            return detailsRaw.isEmpty ? tr("ui.common.unknown") : detailsRaw
        }
    }

    func handleConfigValidationFailure(configPath: String, details: String) {
        let fileName = URL(fileURLWithPath: configPath).lastPathComponent
        appendLog(level: "error", message: tr("log.config.validate_failed", fileName, details))
        self.presentConfigValidationFailedAlert(fileName: fileName, details: details)
    }

    func restartCoreIfNeededForConfigSwitch(previousPath: String?, nextPath: String?) async {
        guard let nextPath else { return }
        guard previousPath != nextPath else { return }
        guard processManager.isRunning else { return }

        self.settingsStore.preserveLocalSettingsOnNextSync = true
        clearProxyPresentation()
        appendLog(level: "info", message: tr("log.config.changed_restart"))
        self.proxyStore.cancelProviderRefresh(reason: "config switch requested")
        await self.restartCore(trigger: .configSwitch)
    }

    func refreshProxyGroupsAfterRestart() async {
        for _ in 0..<8 {
            await refreshProxyGroups()
            if apiStatus == .healthy {
                return
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    func attemptAutoStartIfNeeded() async {
        if didAttemptAutoStart {
            return
        }
        didAttemptAutoStart = true
        await self.startCore(trigger: .auto)
    }

    private func completeCoreBootstrap(
        configPath: String,
        settingsOverlay: EditableSettingsSnapshot,
        isRestart: Bool,
        providerTrigger: ProviderRefreshTrigger) async
    {
        statusText = "Running"
        apiStatus = .healthy
        resetTrafficPresentation()
        ensureAPIClient()
        startPolling()
        await refreshFromAPI(includeSlowCalls: true)
        await self.proxyStore.validateTunPermissionsOnStartup()
        await self.proxyStore.ensureTunMixedStackOnStartupIfNeeded()
        await self.proxyStore.verifyTunAfterOverlayIfNeeded(overlay: settingsOverlay)
        self.proxyStore.enqueueProviderRefresh(trigger: providerTrigger)

        if isRestart {
            await self.refreshProxyGroupsAfterRestart()
        }

        self.proxyStore.scheduleSystemProxyStartupPostflight(
            refreshStatusBeforeOverlay: !isRestart,
            refreshStatusAfterBootstrap: isRestart)

        self.configurationStore.rememberSuccessfulConfig(path: configPath)
        self.startupErrorMessage = nil
        await self.restoreCoreFeaturesAfterStartupIfNeeded()
        enforceNetworkManagedCorePolicyIfNeeded()

        if !isRestart {
            Task { [weak self] in
                await self?.proxyStore.refreshAllGroupLatencies(
                    currentMode: self?.settingsStore.editableSettings.mode ?? .rule)
            }
        }
    }

    private func overlayApplyingPendingCoreFeatureRecovery(_ overlay: EditableSettingsSnapshot)
        -> EditableSettingsSnapshot
    {
        guard let recovery = self.pendingCoreFeatureRecoveryState else { return overlay }
        guard recovery.tunEnabled else { return overlay }
        return overlay.withTunEnabled(true)
    }

    private func currentCoreFeatureRecoverySnapshot() -> CoreFeatureRecoveryState {
        var state = CoreFeatureRecoveryState(
            systemProxyEnabled: self.proxyStore.isSystemProxyEnabled,
            tunEnabled: self.settingsStore.editableSettings.tunEnabled)
        state.merge(with: self.pendingCoreFeatureRecoveryState)
        return state
    }

    private func prepareCoreFeatureRecoveryBeforeCoreTransition(
        fallbackRecovery: CoreFeatureRecoveryState,
        transitionKind: CoreTransitionKind,
        disableRuntimeTunBeforeStop: Bool) async
    {
        let runtimeRunningBeforeTransition = self.isRuntimeRunning
        let isFeatureActive = self.proxyStore.isSystemProxyEnabled
            || self.settingsStore.editableSettings.tunEnabled
        var recovery = (runtimeRunningBeforeTransition && isFeatureActive)
            ? CoreFeatureRecoveryState(
                systemProxyEnabled: self.proxyStore.isSystemProxyEnabled,
                tunEnabled: self.settingsStore.editableSettings.tunEnabled)
            : fallbackRecovery

        recovery.merge(with: self.pendingCoreFeatureRecoveryState)
        self.pendingCoreFeatureRecoveryState = recovery.shouldRecoverAnyFeature ? recovery : nil

        if runtimeRunningBeforeTransition, recovery.tunEnabled {
            if transitionKind == .stop, disableRuntimeTunBeforeStop {
                do {
                    try await self.proxyStore.applyTunRuntimeChange(enabled: false)
                } catch {
                    self.appendLog(
                        level: "error",
                        message: self.tr("log.tun.toggle_failed", self.proxyStore.tunErrorMessage(error)))
                }
            }
            self.settingsStore.editableSettings.tunEnabled = false
            self.appendLog(level: "info", message: self.tr("log.tun.toggled", self.tr("log.tun.disabled")))
        }

        guard self.proxyStore.isSystemProxyEnabled else { return }
        self.proxyStore.isProxySyncing = true
        defer { self.proxyStore.isProxySyncing = false }

        do {
            try await self.proxyStore.applySystemProxy(enabled: false, host: self.controllerHost(), ports: .disabled)
            self.proxyStore.isSystemProxyEnabled = false
            self.proxyStore.systemProxyActiveDisplay = nil
            self.proxyStore.clearSystemProxyOpenFailureHint()
            self.appendLog(
                level: "info",
                message: self.tr("log.system_proxy.toggled", self.tr("log.system_proxy.disabled")))
        } catch {
            self.appendLog(
                level: "error",
                message: self.tr("log.system_proxy.toggle_failed", self.proxyStore.systemProxyErrorMessage(error)))
            await self.proxyStore.refreshSystemProxyHelperStatus()
            await self.proxyStore.refreshSystemProxyStatus()
        }
    }

    func seedCoreFeatureRecoveryFromPersistedQuitState() {
        let wasSystemProxyEnabled = defaults.bool(forKey: systemProxyEnabledOnQuitKey)
        defaults.removeObject(forKey: systemProxyEnabledOnQuitKey)
        guard wasSystemProxyEnabled else { return }
        guard pendingCoreFeatureRecoveryState == nil else { return }
        pendingCoreFeatureRecoveryState = CoreFeatureRecoveryState(
            systemProxyEnabled: true,
            tunEnabled: false)
    }

    func restoreCoreFeaturesAfterStartupIfNeeded() async {
        guard let recovery = self.pendingCoreFeatureRecoveryState else { return }
        guard recovery.shouldRecoverAnyFeature else {
            self.pendingCoreFeatureRecoveryState = nil
            return
        }
        guard self.isRuntimeRunning else { return }

        if self.networkReachabilityStatus == .offline {
            return
        }

        var remainingSystemProxyRecovery = recovery.systemProxyEnabled
        var remainingTunRecovery = recovery.tunEnabled

        if recovery.tunEnabled {
            var tunRestored = false
            do {
                let runtimeConfig = try await self.fetchRuntimeConfigSnapshot()
                if runtimeConfig.tunEnabled != true {
                    try await self.proxyStore.patchTunConfig(enable: true)
                    try await self.proxyStore.verifyTunRuntimeState(expectedEnabled: true)
                    tunRestored = true
                } else if self.settingsStore.editableSettings.tunEnabled {
                    tunRestored = true
                }
            } catch {
                self.appendLog(
                    level: "error",
                    message: self.tr("log.tun.toggle_failed", self.proxyStore.tunErrorMessage(error)))
            }

            if tunRestored {
                self.settingsStore.editableSettings.tunEnabled = true
                self.persistEditableSettingsSnapshot()
                remainingTunRecovery = false
                self.appendLog(level: "info", message: self.tr("log.tun.toggled", self.tr("log.tun.enabled")))
            }
        }

        if recovery.systemProxyEnabled {
            self.proxyStore.isProxySyncing = true
            defer { self.proxyStore.isProxySyncing = false }

            do {
                let target = try await self.proxyStore.resolveSystemProxyTargetFromRuntimeConfig()
                let isAlreadyConfigured = try await self.proxyStore.isSystemProxyConfigured(
                    host: target.host,
                    ports: target.ports)
                if !isAlreadyConfigured {
                    try await self.proxyStore.applySystemProxy(enabled: true, host: target.host, ports: target.ports)
                }
                self.proxyStore.isSystemProxyEnabled = true
                self.proxyStore.clearSystemProxyOpenFailureHint()
                self.proxyStore.systemProxyActiveDisplay = self.proxyStore.buildSystemProxyDisplayString(
                    host: target.host,
                    ports: target.ports)
                remainingSystemProxyRecovery = false
                self.appendLog(
                    level: "info",
                    message: self.tr("log.system_proxy.toggled", self.tr("log.system_proxy.enabled")))
            } catch {
                self.appendLog(
                    level: "error",
                    message: self.tr("log.system_proxy.toggle_failed", self.proxyStore.systemProxyErrorMessage(error)))
                self.proxyStore.updateSystemProxyOpenFailureHint(for: error)
                await self.proxyStore.refreshSystemProxyHelperStatus()
                await self.proxyStore.refreshSystemProxyStatus()
            }
        }

        let remaining = CoreFeatureRecoveryState(
            systemProxyEnabled: remainingSystemProxyRecovery,
            tunEnabled: remainingTunRecovery)
        self.pendingCoreFeatureRecoveryState = remaining.shouldRecoverAnyFeature ? remaining : nil
    }

    func applyMachineTargetEndpoint(_ target: MachineTarget) async {
        self.cancelPolling()
        self.resetTrafficPresentation()
        self.logsStore.clearAllLogs()
        self.clearProxyPresentation()
        self.rulesStore.reset()
        self.connectionsStore.reset()
        self.version = "-"

        switch target {
        case .local:
            self.appendLog(level: "info", message: self.tr("log.remote.switched_to_local"))
            if let configPath = await self.resolveSelectedConfigPath() {
                self.applyExternalControllerFromSelectedConfigFile(configPath: configPath)
            } else {
                let fallback = "127.0.0.1:9090"
                self.controller = fallback
                self.controllerSecret = nil
                self.externalControllerDisplay = fallback
                self.localExternalControllerDisplay = fallback
                self.applyExternalUIConfiguration(hasURL: false, name: nil)
                self.ensureAPIClient()
            }

            self.settingsStore.loadPersistedSettings()
            self.settingsStore.preserveLocalSettingsOnNextSync = true
            self.settingsStore.lastSyncedEditableSettings = nil

        case let .remote(machine):
            self.appendLog(
                level: "info",
                message: self.tr("log.remote.switched_to_remote", machine.name, machine.displayAddress))
            self.controller = machine.controllerAddress
            self.controllerSecret = machine.secret
            self.externalControllerDisplay = machine.displayAddress
            self.applyExternalUIConfiguration(hasURL: false, name: nil)
            self.ensureAPIClient()
            self.settingsStore.lastSyncedEditableSettings = nil
            self.settingsStore.preserveLocalSettingsOnNextSync = false
        }

        await self.refreshFromAPI(includeSlowCalls: true)

        if self.settingsStore.lastSyncedEditableSettings == nil {
            _ = try? await self.fetchRuntimeConfigSnapshot()
        }

        if case .local = target {
            self.refreshSSIDStrategyState(requestAuthorizationIfNeeded: self.configurationStore.ssidStrategyEnabled)
            await self.applySSIDStrategyForCurrentSSIDIfNeeded()
        }

        switch target {
        case .remote:
            self.statusText = (self.apiStatus == .healthy || self.apiStatus == .degraded)
                ? "Running" : "Stopped"
        case .local:
            if !self.processManager.isRunning {
                self.statusText = "Stopped"
            }
        }

        if self.apiStatus == .healthy || self.apiStatus == .degraded {
            self.startPolling()
        }
    }

    func switchToMachineTarget(_ target: MachineTarget) async {
        _ = await self.remoteMachineStore.switchToTarget(target)
    }
}

// MARK: - Maintenance & Updates

extension AppViewModel {
    func upgradeCore() async {
        guard !self.isCoreUpgradeInFlight else { return }

        self.coreUpgradeFeedbackClearTask?.cancel()
        self.coreUpgradeFeedbackClearTask = nil
        self.coreUpgradeState = .running

        do {
            let response: CoreUpgradeResponse = try await self.clientOrThrow().request(.upgradeCore)
            self.applyCoreUpgradeState(self.coreUpgradeState(from: response))
        } catch {
            self.applyCoreUpgradeState(self.coreUpgradeState(from: error))
        }
    }

    func upgradeGeo() async {
        guard !self.isGeoUpdateInFlight else { return }

        self.geoUpdateFeedbackClearTask?.cancel()
        self.geoUpdateFeedbackClearTask = nil
        self.geoUpdateState = .updating

        do {
            try await self.clientOrThrow().requestNoResponse(.upgradeGeo)
            self.applyGeoUpdateState(.succeeded)
        } catch {
            self.applyGeoUpdateState(.failed(message: self.geoUpdateFailureMessage(from: error)))
        }
    }

    func flushFakeIPCache() async {
        await runNoResponseAction(tr("log.action_name.flush_fakeip_cache")) {
            try await self.clientOrThrow().requestNoResponse(.flushFakeIPCache)
        }
    }

    func flushDNSCache() async {
        await runNoResponseAction(tr("log.action_name.flush_dns_cache")) {
            try await self.clientOrThrow().requestNoResponse(.flushDNSCache)
        }
    }

    var isCoreUpgradeInFlight: Bool {
        self.coreUpgradeState == .running
    }

    var isGeoUpdateInFlight: Bool {
        self.geoUpdateState == .updating
    }

    private func applyCoreUpgradeState(_ state: CoreUpgradeState) {
        self.coreUpgradeState = state

        switch state {
        case .idle, .running:
            return
        case .succeeded:
            self.appendLog(level: "info", message: tr("log.core_upgrade.updated"))
            Task { [weak self] in
                await self?.refreshCoreVersionAfterUpgradeIfPossible()
            }
        case let .alreadyLatest(version):
            if let version, !version.isEmpty {
                self.version = AppSemanticVersion.normalizedDisplayVersion(from: version)
                self.appendLog(level: "info", message: tr("log.core_upgrade.latest_version", self.version))
            } else {
                self.appendLog(level: "info", message: tr("log.core_upgrade.latest"))
            }
        case let .failed(message):
            self.appendLog(level: "error", message: tr("log.core_upgrade.failed", message))
        }

        self.scheduleCoreUpgradeFeedbackAutoClear()
    }

    private func applyGeoUpdateState(_ state: GeoUpdateState) {
        self.geoUpdateState = state

        switch state {
        case .idle, .updating:
            return
        case .succeeded:
            self.appendLog(level: "info", message: tr("log.geo_update.updated"))
        case let .failed(message):
            self.appendLog(level: "error", message: tr("log.geo_update.failed", message))
        }

        self.scheduleGeoUpdateFeedbackAutoClear()
    }

    private func scheduleFeedbackAutoClear(
        task: inout Task<Void, Never>?,
        reset: @escaping @MainActor (AppViewModel) -> Void)
    {
        task?.cancel()
        task = Task { [weak self] in
            guard await (try? Task.sleep(nanoseconds: 4_000_000_000)) != nil else { return }
            guard let self else { return }
            reset(self)
        }
    }

    private func scheduleCoreUpgradeFeedbackAutoClear() {
        self.scheduleFeedbackAutoClear(task: &self.coreUpgradeFeedbackClearTask) { vm in
            if !vm.isCoreUpgradeInFlight {
                vm.coreUpgradeState = .idle
            }
        }
    }

    private func scheduleGeoUpdateFeedbackAutoClear() {
        self.scheduleFeedbackAutoClear(task: &self.geoUpdateFeedbackClearTask) { vm in
            if !vm.isGeoUpdateInFlight {
                vm.geoUpdateState = .idle
            }
        }
    }

    private func refreshCoreVersionAfterUpgradeIfPossible() async {
        do {
            try await Task.sleep(nanoseconds: 750_000_000)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        do {
            let versionInfo: VersionInfo = try await self.clientOrThrow().request(.version)
            guard !Task.isCancelled else { return }
            self.version = versionInfo.version
        } catch {}
    }

    private func coreUpgradeState(from response: CoreUpgradeResponse) -> CoreUpgradeState {
        if let status = response.status?.trimmedNonEmpty,
           status.caseInsensitiveCompare("ok") == .orderedSame
        {
            return .succeeded
        }

        if let message = response.message?.trimmedNonEmpty {
            return self.coreUpgradeState(fromMessage: message)
        }

        return .failed(message: tr("ui.common.unknown"))
    }

    private func coreUpgradeState(from error: Error) -> CoreUpgradeState {
        if let apiError = error as? APIError,
           case let .statusCode(_, responseBody) = apiError
        {
            if let data = responseBody.data(using: .utf8),
               let response = try? JSONDecoder().decode(CoreUpgradeResponse.self, from: data)
            {
                let state = self.coreUpgradeState(from: response)
                if case let .failed(message) = state, message == tr("ui.common.unknown") {
                    return self.coreUpgradeState(fromMessage: responseBody)
                }
                return state
            }

            return self.coreUpgradeState(fromMessage: responseBody)
        }

        return self.coreUpgradeState(fromMessage: error.localizedDescription)
    }

    private func geoUpdateFailureMessage(from error: Error) -> String {
        let raw: String = if let apiError = error as? APIError,
                             case let .statusCode(_, responseBody) = apiError
        {
            responseBody
        } else {
            error.localizedDescription
        }

        let trimmed = raw.trimmed
        return trimmed.isEmpty ? tr("ui.common.unknown") : trimmed
    }

    private func coreUpgradeState(fromMessage message: String) -> CoreUpgradeState {
        let trimmedMessage = message.trimmed
        guard !trimmedMessage.isEmpty else {
            return .failed(message: tr("ui.common.unknown"))
        }

        if self.isAlreadyLatestCoreUpgradeMessage(trimmedMessage) {
            return .alreadyLatest(version: self.latestVersion(in: trimmedMessage))
        }

        return .failed(message: trimmedMessage)
    }

    private func isAlreadyLatestCoreUpgradeMessage(_ message: String) -> Bool {
        message.range(
            of: "already using latest version",
            options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static let versionRegex = try? NSRegularExpression(pattern: #"v?\d+(?:\.\d+)+"#)

    private func latestVersion(in message: String) -> String? {
        guard let regex = Self.versionRegex else { return nil }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.matches(in: message, range: range).last,
              let swiftRange = Range(match.range, in: message)
        else {
            return nil
        }

        let raw = String(message[swiftRange])
        return AppSemanticVersion.normalizedDisplayVersion(from: raw)
    }

    var currentAppVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, !short.isEmpty {
            return short
        }
        if let build, !build.isEmpty {
            return build
        }
        return "0.0.1"
    }

    var availableAppUpdate: AppReleaseInfo? {
        guard let latestAppReleaseInfo else { return nil }
        guard !latestAppReleaseInfo.isDraft, !latestAppReleaseInfo.isPrerelease else { return nil }
        guard AppSemanticVersion.isNewerRelease(
            tagName: latestAppReleaseInfo.tagName,
            than: self.currentAppVersionText)
        else {
            return nil
        }
        return latestAppReleaseInfo
    }

    var appReleaseIndexURL: URL? {
        URL(string: "https://github.com/Sitoi/ClashBar/releases")
    }

    func refreshLatestAppRelease() async {
        guard !self.isLatestAppReleaseCheckInFlight else { return }

        self.isLatestAppReleaseCheckInFlight = true
        defer {
            self.isLatestAppReleaseCheckInFlight = false
        }

        do {
            let release = try await AppReleaseService.fetchLatestRelease(currentVersion: self.currentAppVersionText)
            guard !Task.isCancelled else { return }
            guard self.latestAppReleaseInfo != release else { return }
            self.latestAppReleaseInfo = release
        } catch {
            guard !Task.isCancelled else { return }
        }
    }
}

// MARK: - Validation & Controller Config

extension AppViewModel {
    private var defaultControllerAddress: String {
        "127.0.0.1:9090"
    }

    func applyExternalControllerFromConfig(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard self.isValidExternalController(trimmed) else {
            self.appendExternalControllerWarningOnce(
                key: "invalid:\(trimmed)",
                message: "Ignored invalid external-controller value: \(trimmed)")
            return
        }

        if externalControllerDisplay != trimmed {
            externalControllerDisplay = trimmed
        }
        localExternalControllerDisplay = trimmed

        if let host = controllerHost(from: trimmed), !isLoopbackHost(host) {
            self.appendExternalControllerWarningOnce(
                key: "risk:\(host.lowercased())",
                message: "[security] external-controller host is not loopback: \(host)")
        }

        let clientController = self.normalizedControllerForClientAccess(trimmed)
        let didChangeController = controller != clientController
        if didChangeController {
            controller = clientController
        }
        self.refreshControllerUIURL()
        if didChangeController || apiClient == nil {
            ensureAPIClient()
        }
    }

    private func isValidExternalController(_ value: String) -> Bool {
        guard let components = parsedControllerComponents(from: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            return false
        }
        guard scheme == "http" || scheme == "https" else {
            return false
        }
        if let port = components.port {
            return (1...65535).contains(port)
        }
        return true
    }

    func controllerHost(from value: String) -> String? {
        self.parsedControllerComponents(from: value)?.host
    }

    private func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    private func appendExternalControllerWarningOnce(key: String, message: String) {
        if externalControllerWarningKeys.insert(key).inserted {
            appendLog(level: "warning", message: message)
        }
    }

    private func parsedControllerComponents(from value: String) -> URLComponents? {
        let normalized = (value.hasPrefix("http://") || value.hasPrefix("https://")) ? value : "http://\(value)"
        return URLComponents(string: normalized)
    }

    @discardableResult
    func applyExternalControllerFromSelectedConfigFile(configPath: String) -> String {
        guard let raw = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            self.applyExternalControllerFromConfig(self.defaultControllerAddress)
            return self.defaultControllerAddress
        }

        let launchController = self.resolvedControllerFromConfigContent(raw)
        self.applyExternalControllerFromConfig(launchController)

        let parsedSecret = self.parseYAMLScalarValue(forKey: "secret", fromConfigContent: raw)
        self.applyControllerSecretFromConfig(parsedSecret)

        let parsedExternalUIURL = self.parseYAMLScalarValue(forKey: "external-ui-url", fromConfigContent: raw)
        let parsedExternalUIName = self.parseYAMLScalarValue(forKey: "external-ui-name", fromConfigContent: raw)
        self.applyExternalUIConfiguration(
            hasURL: parsedExternalUIURL.trimmedNonEmpty != nil,
            name: parsedExternalUIName)

        return launchController
    }

    private func applyControllerSecretFromConfig(_ rawValue: String?) {
        let normalizedSecret = self.normalizedControllerSecret(rawValue)
        let currentSecret = self.normalizedControllerSecret(controllerSecret)
        if normalizedSecret != currentSecret {
            controllerSecret = normalizedSecret
        }
        self.refreshControllerUIURL()
        ensureAPIClient()
    }

    func applyExternalUIConfiguration(hasURL: Bool, name: String?) {
        self.hasConfiguredExternalUI = hasURL
        self.configuredExternalUIName = hasURL ? self.normalizedExternalUIName(name) : nil
        self.refreshControllerUIURL()
    }

    func refreshControllerUIURL() {
        let nextURL = self.makeControllerUIURL(
            self.controller,
            secret: self.controllerSecret,
            hasConfiguredExternalUI: self.hasConfiguredExternalUI,
            externalUIName: self.configuredExternalUIName)
        if self.controllerUIURL != nextURL {
            self.controllerUIURL = nextURL
        }
    }

    private func parseYAMLScalarValue(forKey key: String, fromConfigContent raw: String) -> String? {
        for line in raw.split(whereSeparator: \.isNewline) {
            guard !line.starts(with: " ") && !line.starts(with: "\t") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let afterKey = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard afterKey.hasPrefix(":") else { continue }

            var value = String(afterKey.dropFirst().trimmingCharacters(in: .whitespaces))
            if value.hasPrefix("\""), let endQuote = value.dropFirst().firstIndex(of: "\"") {
                value = String(value[value.index(after: value.startIndex)..<endQuote])
            } else if value.hasPrefix("'"), let endQuote = value.dropFirst().firstIndex(of: "'") {
                value = String(value[value.index(after: value.startIndex)..<endQuote])
            } else if let commentIndex = value.firstIndex(of: "#") {
                value = String(value[..<commentIndex]).trimmingCharacters(in: .whitespaces)
            }

            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedValue.isEmpty || trimmedValue == "~" || trimmedValue.lowercased() == "null" {
                return nil
            }
            return trimmedValue
        }
        return nil
    }

    private func normalizedControllerSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "~", trimmed.lowercased() != "null" else { return nil }
        return trimmed
    }

    private func normalizedExternalUIName(_ value: String?) -> String? {
        guard let trimmed = value?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)),
            !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func resolvedControllerFromConfigContent(_ raw: String) -> String {
        if let parsed = self.parseYAMLScalarValue(forKey: "external-controller", fromConfigContent: raw) {
            guard self.isValidExternalController(parsed) else {
                self.appendExternalControllerWarningOnce(
                    key: "invalid:\(parsed)",
                    message: "Ignored invalid external-controller value: \(parsed)")
                return self.defaultControllerAddress
            }
            return parsed
        }
        return self.defaultControllerAddress
    }

    private func normalizedControllerForClientAccess(_ value: String) -> String {
        guard var components = parsedControllerComponents(from: value),
              let host = components.host
        else {
            return value
        }

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let replacementHost: String
        switch normalizedHost {
        case "0.0.0.0":
            replacementHost = "127.0.0.1"
        case "::", "0:0:0:0:0:0:0:0":
            replacementHost = "::1"
        default:
            return value
        }

        components.host = replacementHost
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return components.string ?? value
        }

        guard let hostPort = hostPortString(from: components) else {
            return value
        }
        return hostPort
    }

    private func hostPortString(from components: URLComponents) -> String? {
        guard let host = components.host, !host.isEmpty else {
            return nil
        }
        let hostSegment = host.contains(":") ? "[\(host)]" : host
        if let port = components.port {
            return "\(hostSegment):\(port)"
        }
        return hostSegment
    }
}
