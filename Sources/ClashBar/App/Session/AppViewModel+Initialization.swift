import Foundation
import MihomoKit

@MainActor
extension AppViewModel {
    func configureManagedProcessCallbacks() {
        self.mihomoBinaryPath = self.processManager.detectedBinaryPath ?? "-"
        self.processManager.onLog = { [weak self] line in
            Task { @MainActor in
                guard self?.isRemoteTarget != true else { return }
                self?.appendMihomoLog(level: "info", message: line)
            }
        }
        self.processManager.onTermination = { [weak self] code in
            Task { @MainActor in
                guard self?.isRemoteTarget != true else { return }
                let message = self?.tr("log.process.terminated", code) ?? ""
                self?.statusText = "Failed"
                self?.apiStatus = .failed
                self?.resetTrafficPresentation()
                self?.appendLog(level: "error", message: message)
                self?.cancelPolling()
                if self?.coreActionState == .idle, let self, !message.isEmpty {
                    self.presentCoreFailureAlert(
                        title: self.tr("app.core.alert.process_terminated.title"),
                        message: message,
                        dedupeKey: "core-process-terminated",
                        style: .critical)
                }
            }
        }
    }

    func bootstrapDirectoriesAndLogs() {
        do {
            try self.workingDirectoryManager.bootstrapDirectories()
            Task { [clashbarLogStore, mihomoLogStore] in
                await clashbarLogStore.ensureLogFileExists()
                await mihomoLogStore.ensureLogFileExists()
            }
            self.configurationStore.seedBundledConfigIfNeeded()
        } catch {
            appendLog(level: "error", message: tr("log.working_dir_init_failed", error.localizedDescription))
        }
    }

    func start() {
        guard !self.didStart else { return }
        self.didStart = true
        self.bootstrapDirectoriesAndLogs()
        self.performDeferredInitialization()
    }

    private func performDeferredInitialization() {
        restoreSavedConfigDirectory()
        restoreLastSuccessfulConfigIfAvailable()
        self.configurationStore.subscriptions = self.configurationStore.loadSubscriptions()
        pruneRemoteConfigSubscriptionsIfNeeded()
        self.configurationStore.ssidStrategyRules = self.configurationStore.loadSSIDStrategyRules()
        self.pruneSSIDStrategyRulesIfNeeded()
        self.remoteMachineStore.resetActiveTarget()
        if let configPath = self.configurationStore.selectedConfig?.path {
            _ = self.applyExternalControllerFromSelectedConfigFile(configPath: configPath)
        } else {
            self.refreshControllerUIURL()
        }
        self.settingsStore.loadPersistedSettings()
        self.settingsStore.preserveLocalSettingsOnNextSync = true

        self.startupRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshFromAPI(includeSlowCalls: true)
            self.seedCoreFeatureRecoveryFromPersistedQuitState()
            if self.proxyStore.hasSystemProxyOpenIntent {
                await self.systemProxyService.warmUpHelperIfPossible()
                await self.proxyStore.refreshSystemProxyHelperStatus()
                await self.proxyStore.refreshSystemProxyStatus()
                await self.proxyStore.ensureSystemProxyConsistencyOnFirstLaunchIfNeeded()
            } else {
                self.proxyStore.resetSystemProxyObservedState()
                self.proxyStore.didCheckSystemProxyConsistencyOnLaunch = true
            }
        }

        self.startConfigDirectoryMonitoringIfNeeded()
        if self.autoStartCore {
            if !self.shouldDeferAutoStartForMissingManagedCore() {
                self.autoStartTask = Task { [weak self] in
                    await self?.attemptAutoStartIfNeeded()
                }
            }
        }

        self.refreshSSIDStrategyState(requestAuthorizationIfNeeded: self.configurationStore.ssidStrategyEnabled)
        self.updateNetworkReachabilityMonitoringState()
        self.refreshMenuBarDisplaySnapshotIfNeeded()
    }
}

extension AppViewModel {
    static func resolveBundledMihomoCoreFlag() -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ClashBarBundlesMihomoCore") else {
            return true
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return NSString(string: string).boolValue
        }
        return true
    }

    func hasInstalledManagedMihomoCore() -> Bool {
        FileManager.default.fileExists(atPath: workingDirectoryManager.managedMihomoBinaryURL.path)
    }

    func shouldDeferAutoStartForMissingManagedCore() -> Bool {
        !bundlesMihomoCore && !self.hasInstalledManagedMihomoCore()
    }

    func coreErrorMessage(_ error: Error) -> String {
        if let binaryResolutionError = error as? MihomoBinaryResolutionError {
            switch binaryResolutionError {
            case let .binaryNotFound(expectedDirectory):
                return tr("app.core.error.binary_not_found", expectedDirectory)
            }
        }

        return error.localizedDescription
    }

    func resolveSelectedConfigPath() async -> String? {
        self.applySelectedConfig(self.configurationStore.resolveSelectedConfig())
    }

    private func applySelectedConfig(_ selected: URL?) -> String? {
        guard let selected else { return nil }
        let selectedPath = self.syncSelectedConfigSelection(selected)
        self.syncConfigDisplayState()
        return selectedPath
    }

    @discardableResult
    func syncSelectedConfigSelection(_ selected: URL?) -> String? {
        guard let selected else {
            self.configurationStore.selectedConfigName = "-"
            self.configurationStore.rememberSelection(named: nil)
            return nil
        }
        self.configurationStore.selectedConfigName = selected.lastPathComponent
        self.configurationStore.rememberSelection(named: selected.lastPathComponent)
        return selected.path
    }

    func restoreSavedConfigDirectory() {
        configurationStore.setConfigDirectory(workingDirectoryManager.configDirectoryURL)
        if let selected = configurationStore.selectedConfig {
            _ = self.syncSelectedConfigSelection(selected)
        }
        self.syncConfigDisplayState()
    }

    func restoreLastSuccessfulConfigIfAvailable() {
        guard let matched = self.configurationStore.restoreLastSuccessfulConfig() else { return }
        _ = self.syncSelectedConfigSelection(matched)
        self.syncConfigDisplayState()
    }

    func syncConfigDisplayState() {
        self.configurationStore.configDirectoryPath = configurationStore.configDirectory?.path ?? "-"
        self.configurationStore.availableConfigFileNames = configurationStore.availableConfigs.map(\.lastPathComponent)
        if self.configurationStore.selectedConfigName == "-",
           let first = self.configurationStore.availableConfigFileNames.first
        {
            self.configurationStore.selectedConfigName = first
        }
        self.pruneSSIDStrategyRulesIfNeeded()
        self.pruneRemoteConfigSubscriptionsIfNeeded()
        self.refreshRemoteConfigMenuStates()
    }

    func ensureAPIClient() {
        if let apiClient {
            apiClient.updateCredentials(controller: controller, secret: controllerSecret)
        } else {
            apiClient = MihomoAPIService(controller: controller, secret: controllerSecret)
        }
    }

    func persistEditableSettingsSnapshot() {
        guard !self.settingsStore.suppressSettingsPersistence else { return }
        guard !self.isRemoteTarget else { return }
        self.encodeToDefaults(self.settingsStore.editableSettings, key: editableSettingsSnapshotKey)
    }

    func loadPersistedEditableSettingsSnapshot() -> EditableSettingsSnapshot? {
        self.decodeFromDefaults(EditableSettingsSnapshot.self, key: editableSettingsSnapshotKey)
    }

    func persistSystemProxyExceptions() {
        self.encodeToDefaults(self.proxyStore.lastSavedSystemProxyExceptions, key: systemProxyExceptionsKey)
    }

    func decodeFromDefaults<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func encodeToDefaults(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func loadPersistedSystemProxyExceptions() -> [String]? {
        guard let values = self.decodeFromDefaults([String].self, key: systemProxyExceptionsKey) else { return nil }
        return self.proxyStore.normalizedSystemProxyExceptionValues(values)
    }

    func loadPersistedUILanguage() -> AppLanguage {
        if let raw = defaults.string(forKey: uiLanguageKey),
           let language = AppLanguage(rawValue: raw)
        {
            return language
        }
        defaults.set(AppLanguage.zhHans.rawValue, forKey: uiLanguageKey)
        return .zhHans
    }

    func loadPersistedAppearanceMode() -> AppAppearanceMode {
        if let raw = defaults.string(forKey: appearanceModeKey),
           let mode = AppAppearanceMode(rawValue: raw)
        {
            return mode
        }
        defaults.set(AppAppearanceMode.system.rawValue, forKey: appearanceModeKey)
        return .system
    }

    func pruneRemoteConfigSubscriptionsIfNeeded() {
        _ = self.configurationStore.pruneSubscriptions(
            availableFileNames: self.configurationStore.availableConfigFileNames)
    }

    func pruneSSIDStrategyRulesIfNeeded() {
        guard self.configurationStore.configDirectory != nil else { return }

        let validConfigNames = Set(self.configurationStore.availableConfigFileNames.map(\.trimmed))
        let nextRules = SSIDStrategyRule.normalized(self.configurationStore.ssidStrategyRules).filter {
            validConfigNames.contains($0.configFileName)
        }
        guard nextRules != self.configurationStore.ssidStrategyRules else { return }

        self.configurationStore.ssidStrategyRules = nextRules
        self.configurationStore.persistSSIDStrategyRules(nextRules)
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = self.launchAtLoginService.isEnabled
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginErrorMessage = nil

        do {
            try self.launchAtLoginService.setEnabled(enabled)
            launchAtLoginEnabled = self.launchAtLoginService.isEnabled
        } catch {
            launchAtLoginEnabled = self.launchAtLoginService.isEnabled
            launchAtLoginErrorMessage = self.launchAtLoginMessage(for: error)
            appendLog(level: "error", message: tr("log.launch_at_login.toggle_failed", error.localizedDescription))
        }
    }

    private func launchAtLoginMessage(for error: Error) -> String {
        guard let launchError = error as? AppLaunchServiceError else {
            return error.localizedDescription
        }

        switch launchError {
        case .unsupportedEnvironment:
            return tr("app.launch_at_login.error.unsupported_environment")
        case .requiresApproval:
            return tr("app.launch_at_login.error.requires_approval")
        case let .registrationFailed(message):
            return tr("app.launch_at_login.error.register_failed", message)
        case let .unregistrationFailed(message):
            return tr("app.launch_at_login.error.unregister_failed", message)
        }
    }
}
