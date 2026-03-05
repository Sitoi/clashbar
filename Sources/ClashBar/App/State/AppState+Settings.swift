import Foundation

@MainActor
extension AppState {
    func applySettingAllowLan(_ value: Bool) async {
        await self.applyBooleanSetting(\.settingsAllowLan, configKey: "allow-lan", value: value)
    }

    func applySettingIPv6(_ value: Bool) async {
        await self.applyBooleanSetting(\.settingsIPv6, configKey: "ipv6", value: value)
    }

    func applySettingUnifiedDelay(_ value: Bool) async {
        await self.applyBooleanSetting(\.settingsUnifiedDelay, configKey: "unified-delay", value: value)
    }

    func applySettingTunMode(_ value: Bool) async {
        await toggleTunMode(value)
    }

    func applySettingLogLevel(_ value: String) async {
        settingsLogLevel = value
        await self.applySettingEnumLogLevel(value)
    }

    func applyProxyPorts(autoSaved: Bool = false) async {
        guard let body = validatedPortPatchBody(
            fields: proxyPortFields,
            errorMessageKey: "app.settings.error.port_range",
            skipEmptyValues: false) else { return }

        let syncingKey = autoSaved ? "ports-auto" : "ports"
        let successMessage = autoSaved ? tr("app.settings.saved.ports_auto") : tr("app.settings.saved.ports")
        await self.patchConfigBody(body, syncingKey: syncingKey, successMessage: successMessage)
    }

    func scheduleProxyPortsAutoSaveIfNeeded() {
        guard !suppressSettingsPersistence else { return }
        guard settingsSyncingKey == nil else { return }

        proxyPortsAutoSaveTask?.cancel()
        proxyPortsAutoSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }

            guard let self else { return }
            if Task.isCancelled { return }
            // Clear the tracking reference before saving so patchConfigBody()
            // will not cancel the currently running autosave task itself.
            self.proxyPortsAutoSaveTask = nil
            await self.applyProxyPorts(autoSaved: true)
        }
    }

    func cancelProxyPortsAutoSave() {
        proxyPortsAutoSaveTask?.cancel()
        proxyPortsAutoSaveTask = nil
    }

    func syncEditableSettings(from config: ConfigSnapshot) {
        let incoming = EditableSettingsSnapshot(config: config)

        if preserveLocalSettingsOnNextSync {
            preserveLocalSettingsOnNextSync = false
            lastSyncedEditableSettings = incoming
            persistEditableSettingsSnapshot()
            return
        }

        guard let previous = lastSyncedEditableSettings else {
            self.applyEditableSettingsSnapshotToUI(incoming)
            lastSyncedEditableSettings = incoming
            persistEditableSettingsSnapshot()
            return
        }

        suppressSettingsPersistence = true
        self.syncEditableFields(
            from: previous,
            to: incoming,
            fields: [
                (\.settingsAllowLan, \.allowLan),
                (\.settingsIPv6, \.ipv6),
                (\.settingsUnifiedDelay, \.unifiedDelay),
                (\.isTunEnabled, \.tunEnabled),
            ])

        self.syncEditableFields(
            from: previous,
            to: incoming,
            fields: [
                (\.settingsLogLevel, \.logLevel),
                (\.settingsPort, \.port),
                (\.settingsSocksPort, \.socksPort),
                (\.settingsMixedPort, \.mixedPort),
                (\.settingsRedirPort, \.redirPort),
                (\.settingsTProxyPort, \.tproxyPort),
            ])
        suppressSettingsPersistence = false

        lastSyncedEditableSettings = incoming
        persistEditableSettingsSnapshot()
    }

    func currentEditableSettingsSnapshot() -> EditableSettingsSnapshot {
        EditableSettingsSnapshot(
            allowLan: settingsAllowLan,
            ipv6: settingsIPv6,
            unifiedDelay: settingsUnifiedDelay,
            tunEnabled: isTunEnabled,
            logLevel: settingsLogLevel,
            port: settingsPort,
            socksPort: settingsSocksPort,
            mixedPort: settingsMixedPort,
            redirPort: settingsRedirPort,
            tproxyPort: settingsTProxyPort)
    }

    func applyPendingConfigSwitchSettingsOverlayIfNeeded() async {
        guard let overlay = pendingConfigSwitchOverlaySettings else { return }
        pendingConfigSwitchOverlaySettings = nil
        _ = await self.applyEditableSettingsOverlay(
            overlay,
            syncingKey: "config-switch-overlay",
            successMessage: tr("app.settings.overlay_success"))
    }

    func applyPendingAppLaunchSettingsOverlayIfNeeded() async {
        guard let overlay = pendingAppLaunchOverlaySettings else { return }
        guard apiStatus == .healthy else { return }
        pendingAppLaunchOverlaySettings = nil
        _ = await self.applyEditableSettingsOverlay(
            overlay,
            syncingKey: "app-launch-overlay",
            successMessage: "")
    }

    func syncEditableSettingsOverlayForCoreBootstrap(
        _ overlay: EditableSettingsSnapshot,
        syncingKey: String) async
    {
        self.deferredEditableSettingsOverlay = (snapshot: overlay, syncingKey: syncingKey)

        if await self.applyDeferredEditableSettingsOverlayIfPossible() {
            self.deferredEditableSettingsOverlayTask?.cancel()
            self.deferredEditableSettingsOverlayTask = nil
            return
        }

        self.scheduleDeferredEditableSettingsOverlaySync()
    }

    func cancelDeferredEditableSettingsOverlaySync() {
        self.deferredEditableSettingsOverlayTask?.cancel()
        self.deferredEditableSettingsOverlayTask = nil
        self.deferredEditableSettingsOverlay = nil
    }

    @discardableResult
    func applyEditableSettingsOverlay(
        _ overlay: EditableSettingsSnapshot,
        syncingKey: String,
        successMessage: String) async -> Bool
    {
        let fallback = lastSyncedEditableSettings
        let resolvedLogLevel = overlay.logLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (fallback?.logLevel ?? ConfigLogLevel.info.rawValue)
            : overlay.logLevel

        guard ConfigLogLevel(rawValue: resolvedLogLevel) != nil else {
            settingsErrorMessage = tr("app.settings.error.overlay_invalid_log_level", resolvedLogLevel)
            settingsSavedMessage = nil
            return false
        }

        let resolvedPortFields = self.resolvedOverlayPortFields(overlay: overlay, fallback: fallback)
        guard let portBody = validatedPortPatchBody(
            fields: resolvedPortFields,
            errorMessageKey: "app.settings.error.overlay_port_range",
            skipEmptyValues: true)
        else { return false }

        var body: [String: ConfigPatchValue] = [
            "allow-lan": .bool(overlay.allowLan),
            "ipv6": .bool(overlay.ipv6),
            "unified-delay": .bool(overlay.unifiedDelay),
            "tun": .object(["enable": .bool(overlay.tunEnabled)]),
            "log-level": .string(resolvedLogLevel),
        ]
        for (key, value) in portBody {
            body[key] = value
        }

        return await self.patchConfigBody(body, syncingKey: syncingKey, successMessage: successMessage)
    }

    func effectiveMixedPort() -> Int {
        if mixedPort > 0 {
            return mixedPort
        }
        let trimmed = settingsMixedPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed), (1...65535).contains(value) {
            return value
        }
        return 7890
    }

    func applyEditableSettingsSnapshotToUI(_ snapshot: EditableSettingsSnapshot) {
        suppressSettingsPersistence = true
        settingsAllowLan = snapshot.allowLan
        settingsIPv6 = snapshot.ipv6
        settingsUnifiedDelay = snapshot.unifiedDelay
        isTunEnabled = snapshot.tunEnabled
        settingsLogLevel = snapshot.logLevel
        settingsPort = snapshot.port
        settingsSocksPort = snapshot.socksPort
        settingsMixedPort = snapshot.mixedPort
        settingsRedirPort = snapshot.redirPort
        settingsTProxyPort = snapshot.tproxyPort
        suppressSettingsPersistence = false
    }

    func applySettingBool(key: String, value: Bool) async {
        await self.patchSingleConfig(key, value: .bool(value))
    }

    func applySettingEnumLogLevel(_ value: String) async {
        guard ConfigLogLevel(rawValue: value) != nil else {
            settingsErrorMessage = tr("app.settings.error.invalid_log_level", value)
            settingsSavedMessage = nil
            return
        }
        await self.patchSingleConfig("log-level", value: .string(value))
    }

    func patchSingleConfig(_ key: String, value: ConfigPatchValue) async {
        _ = await self.patchConfigBody(
            [key: value],
            syncingKey: key,
            successMessage: tr("app.settings.saved.single_key", key))
    }

    @discardableResult
    func patchConfigBody(_ body: [String: ConfigPatchValue], syncingKey: String, successMessage: String) async -> Bool {
        self.cancelProxyPortsAutoSave()
        settingsFeedbackClearTask?.cancel()
        settingsFeedbackClearTask = nil
        settingsSyncingKey = syncingKey
        settingsErrorMessage = nil
        settingsSavedMessage = nil
        defer { settingsSyncingKey = nil }
        let shouldSyncSystemProxyPort = body.keys.contains { key in
            key == "mixed-port" || key == "port" || key == "socks-port"
        }
        let previousSystemProxyPorts =
            await previousSystemProxyPortsForSyncIfNeeded(shouldSync: shouldSyncSystemProxyPort)

        do {
            ensureAPIClient()
            let payload = body.mapValues(\.jsonValue)
            try await self.settingsPatchTransport().requestNoResponse(.patchConfigs(body: payload))
            settingsSavedMessage = successMessage
            self.scheduleSettingsFeedbackAutoClearIfNeeded(message: successMessage)
            await refreshFromAPI(includeSlowCalls: false)
            await self.syncSystemProxyPortIfNeeded(
                shouldSync: shouldSyncSystemProxyPort,
                previousPorts: previousSystemProxyPorts)
            return true
        } catch {
            let message = tr("app.settings.error.save_failed", syncingKey, error.localizedDescription)
            if self.isOverlaySyncingKey(syncingKey) {
                appendLog(level: "error", message: message)
            } else {
                settingsErrorMessage = message
            }
            settingsSavedMessage = nil
            await refreshFromAPI(includeSlowCalls: false)
            return false
        }
    }

    private func isOverlaySyncingKey(_ syncingKey: String) -> Bool {
        syncingKey.hasSuffix("-overlay")
    }

    private func scheduleDeferredEditableSettingsOverlaySync() {
        self.deferredEditableSettingsOverlayTask?.cancel()
        self.deferredEditableSettingsOverlayTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<120 {
                if Task.isCancelled { return }
                guard self.isRuntimeRunning else { return }
                if await self.applyDeferredEditableSettingsOverlayIfPossible() {
                    self.deferredEditableSettingsOverlayTask = nil
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
            }

            self.deferredEditableSettingsOverlayTask = nil
        }
    }

    private func applyDeferredEditableSettingsOverlayIfPossible() async -> Bool {
        guard let deferred = self.deferredEditableSettingsOverlay else { return true }
        guard await self.isCoreAPIReachableForOverlaySync() else { return false }

        let applied = await self.applyEditableSettingsOverlay(
            deferred.snapshot,
            syncingKey: deferred.syncingKey,
            successMessage: "")
        if applied {
            self.deferredEditableSettingsOverlay = nil
        }
        return applied
    }

    private func isCoreAPIReachableForOverlaySync() async -> Bool {
        do {
            let client = try self.clientOrThrow()
            let _: VersionInfo = try await client.request(.version)
            return true
        } catch {
            return false
        }
    }

    func scheduleSettingsFeedbackAutoClearIfNeeded(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        settingsFeedbackClearTask?.cancel()
        settingsFeedbackClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }

            guard let self else { return }
            if self.settingsSavedMessage == message {
                self.settingsSavedMessage = nil
            }
        }
    }

    func clientOrThrow() throws -> MihomoAPIClient {
        if apiClient == nil {
            ensureAPIClient()
        }
        if let apiClient {
            return apiClient
        }
        throw APIError.invalidURL
    }

    func modeSwitchTransport() throws -> MihomoAPITransporting {
        try self.resolvedTransport(override: modeSwitchTransportOverride)
    }

    func settingsPatchTransport() throws -> MihomoAPITransporting {
        try self.resolvedTransport(override: settingsPatchTransportOverride)
    }

    private func previousSystemProxyPortsForSyncIfNeeded(shouldSync: Bool) async -> SystemProxyPorts? {
        guard shouldSync, isSystemProxyEnabled else { return nil }
        do {
            let client = try clientOrThrow()
            let config: ConfigSnapshot = try await client.request(.getConfigs)
            return systemProxyPorts(from: config)
        } catch {
            return currentSystemProxyPortsFromState()
        }
    }

    private func syncSystemProxyPortIfNeeded(shouldSync: Bool, previousPorts: SystemProxyPorts?) async {
        guard shouldSync, isSystemProxyEnabled else { return }

        do {
            let target = try await resolveSystemProxyTargetFromRuntimeConfig()
            try await applySystemProxy(enabled: true, host: target.host, ports: target.ports)
            appendLog(level: "info", message: tr("log.system_proxy.port_synced", target.ports.primaryPort ?? 0))

            if let previousPorts, previousPorts != target.ports {
                await closeAllConnections()
            }
        } catch {
            appendLog(level: "error", message: tr("log.system_proxy.port_sync_failed", systemProxyErrorMessage(error)))
        }
    }

    private func applyBooleanSetting(
        _ keyPath: ReferenceWritableKeyPath<AppState, Bool>,
        configKey: String,
        value: Bool) async
    {
        self[keyPath: keyPath] = value
        await self.applySettingBool(key: configKey, value: value)
    }

    private func validatedPort(_ textValue: String, key: String, errorMessageKey: String) -> Int? {
        let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intValue = Int(trimmed), (0...65535).contains(intValue) else {
            settingsErrorMessage = tr(errorMessageKey, key)
            settingsSavedMessage = nil
            return nil
        }
        return intValue
    }

    private var proxyPortFields: [(key: String, value: String)] {
        [
            ("port", settingsPort),
            ("socks-port", settingsSocksPort),
            ("mixed-port", settingsMixedPort),
            ("redir-port", settingsRedirPort),
            ("tproxy-port", settingsTProxyPort),
        ]
    }

    private func resolvedOverlayPortFields(
        overlay: EditableSettingsSnapshot,
        fallback: EditableSettingsSnapshot?) -> [(key: String, value: String)]
    {
        [
            ("port", self.resolvedOverlayPortValue(overlay.port, fallback: fallback?.port ?? "")),
            ("socks-port", self.resolvedOverlayPortValue(overlay.socksPort, fallback: fallback?.socksPort ?? "")),
            ("mixed-port", self.resolvedOverlayPortValue(overlay.mixedPort, fallback: fallback?.mixedPort ?? "")),
            ("redir-port", self.resolvedOverlayPortValue(overlay.redirPort, fallback: fallback?.redirPort ?? "")),
            ("tproxy-port", self.resolvedOverlayPortValue(overlay.tproxyPort, fallback: fallback?.tproxyPort ?? "")),
        ]
    }

    private func resolvedOverlayPortValue(_ overlayValue: String, fallback: String) -> String {
        let overlayTrimmed = overlayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard overlayTrimmed.isEmpty else { return overlayTrimmed }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedPortPatchBody(
        fields: [(key: String, value: String)],
        errorMessageKey: String,
        skipEmptyValues: Bool) -> [String: ConfigPatchValue]?
    {
        var body: [String: ConfigPatchValue] = [:]
        for field in fields {
            let trimmedValue = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if skipEmptyValues, trimmedValue.isEmpty {
                continue
            }
            guard let intValue = validatedPort(
                trimmedValue,
                key: field.key,
                errorMessageKey: errorMessageKey) else { return nil }
            body[field.key] = .int(intValue)
        }
        return body
    }

    private func syncEditableFields<Value: Equatable>(
        from previous: EditableSettingsSnapshot,
        to incoming: EditableSettingsSnapshot,
        fields: [(ReferenceWritableKeyPath<AppState, Value>, KeyPath<EditableSettingsSnapshot, Value>)])
    {
        for (stateKeyPath, snapshotKeyPath) in fields {
            guard self[keyPath: stateKeyPath] == previous[keyPath: snapshotKeyPath] else { continue }
            self[keyPath: stateKeyPath] = incoming[keyPath: snapshotKeyPath]
        }
    }

    private func resolvedTransport(override: MihomoAPITransporting?) throws -> MihomoAPITransporting {
        if let override {
            return override
        }
        return try self.clientOrThrow()
    }
}
