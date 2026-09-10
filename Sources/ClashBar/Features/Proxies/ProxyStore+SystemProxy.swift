import Foundation
import MihomoKit

@MainActor
extension ProxyStore {
    static let defaultSystemProxyExceptions: [String] = [
        "::1",
        "*.local",
        "<local>",
        "localhost",
        "127.0.0.1",
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12",
    ]

    var hasPendingSystemProxyExceptionsChanges: Bool {
        self.currentSystemProxyExceptionValues() != self.lastSavedSystemProxyExceptions
    }

    var canAddSystemProxyException: Bool {
        self.systemProxyNewException.trimmedNonEmpty != nil
    }

    func addSystemProxyExceptionDraft() {
        guard let value = self.systemProxyNewException.trimmedNonEmpty else { return }
        let existing = Set(self.currentSystemProxyExceptionValues().map { $0.lowercased() })
        guard !existing.contains(value.lowercased()) else {
            self.systemProxyNewException = ""
            return
        }

        self.systemProxyExceptions.append(EditableSystemProxyException(value: value))
        self.systemProxyNewException = ""
    }

    func removeSystemProxyExceptionDraft(id: EditableSystemProxyException.ID) {
        self.systemProxyExceptions.removeAll { $0.id == id }
    }

    func replaceSystemProxyExceptionsDraft(with values: [String]) {
        self.systemProxyExceptions = self.systemProxyExceptionRows(from: values)
        self.systemProxyNewException = ""
    }

    func restoreDefaultSystemProxyExceptionsDraft() {
        self.replaceSystemProxyExceptionsDraft(with: Self.defaultSystemProxyExceptions)
    }

    func saveSystemProxyExceptions() async {
        let normalized = self.currentSystemProxyExceptionValues()
        self.replaceSystemProxyExceptionsDraft(with: normalized)

        let success = await self.runSystemProxySettingsOperation(
            syncingKey: "system-proxy-exceptions",
            successMessage: tr("app.settings.saved.system_proxy_exceptions"))
        {
            try await self.systemProxyService.setExceptionsList(normalized)
        }

        guard success else { return }
        self.lastSavedSystemProxyExceptions = normalized
        self.saveSystemProxyExceptionsToDefaults(normalized)
    }

    func refreshSystemProxyExceptionsFromSystemIfPossible(overwriteEmpty: Bool = false) async {
        guard !self.hasPendingSystemProxyExceptionsChanges else { return }

        do {
            let values = try await self.systemProxyService.readExceptionsList()
            let normalized = self.normalizedSystemProxyExceptionValues(values)
            guard overwriteEmpty || !normalized.isEmpty else { return }
            self.replaceSystemProxyExceptionsDraft(with: normalized)
            self.lastSavedSystemProxyExceptions = normalized
            self.saveSystemProxyExceptionsToDefaults(normalized)
        } catch {
            return
        }
    }

    func applyCurrentSystemProxyExceptionsIfNeeded() async throws {
        try await self.systemProxyService.setExceptionsList(self.currentSystemProxyExceptionValues())
    }

    var isSystemProxyUsingRemoteCore: Bool {
        guard self.isSystemProxyEnabled,
              let activeDisplay = self.systemProxyActiveDisplay?.trimmedNonEmpty,
              let activeHost = self.controllerHost(from: activeDisplay)?.trimmedNonEmpty
        else {
            return false
        }

        let localHost = self.controllerHost(from: self.localExternalControllerDisplay)?
            .trimmedNonEmpty ?? "127.0.0.1"
        return self.normalizedSystemProxyComparisonHost(activeHost) != self
            .normalizedSystemProxyComparisonHost(localHost)
    }

    func clearSystemProxyOpenFailureHint() {
        self.systemProxyOpenFailureHint = nil
    }

    func updateSystemProxyOpenFailureHint(for error: Error) {
        self.systemProxyOpenFailureHint = self.systemProxyFailureHintMessage(for: error)
    }

    func updateSystemProxyOpenFailureHint(for reason: SystemProxyHelperFailureReason) {
        self.systemProxyOpenFailureHint = self.systemProxyFailureReasonMessage(for: reason)
    }

    var hasSystemProxyOpenIntent: Bool {
        self.isSystemProxyEnabled
            || self.systemProxyEnableIntentInFlight
            || (self.pendingCoreFeatureRecoveryState?.systemProxyEnabled ?? false)
            || self.systemProxyEnabledOnQuit
    }

    func resetSystemProxyObservedState() {
        self.systemProxyBackgroundActivityAllowed = nil
        self.systemProxyHelperProcessRunning = nil
        self.systemProxyHelperFailureReason = nil
        self.systemProxyHelperFailureMessage = nil
        if !self.isSystemProxyEnabled {
            self.systemProxyActiveDisplay = nil
        }
    }

    func applyHelperHealthSnapshot(_ snapshot: SystemProxyHelperHealthSnapshot) {
        let previousReason = self.systemProxyHelperFailureReason
        let previousMessage = self.systemProxyHelperFailureMessage

        self.systemProxyBackgroundActivityAllowed = snapshot.backgroundActivityAllowed
        self.systemProxyHelperProcessRunning = snapshot.processRunning
        self.systemProxyHelperFailureReason = snapshot.failureReason
        self.systemProxyHelperFailureMessage = snapshot.rawMessage

        guard let failureReason = snapshot.failureReason else { return }

        if snapshot.rawMessage != previousMessage || failureReason != previousReason {
            let message = snapshot.rawMessage ?? self.systemProxyFailureReasonMessage(for: failureReason)
            self.appendLog(level: "error", message: tr("log.system_proxy.helper_failed", message))
        }

        if self.hasSystemProxyOpenIntent || self.systemProxyEnableIntentInFlight {
            self.updateSystemProxyOpenFailureHint(for: failureReason)
        }
    }

    func applySystemProxy(enabled: Bool, host: String, ports: SystemProxyPorts) async throws {
        try await self.systemProxyService.apply(enabled: enabled, host: host, ports: ports)
    }

    func readSystemProxyEnabledState() async throws -> Bool {
        try await self.systemProxyService.isEnabled()
    }

    func readSystemProxyActiveDisplay() async throws -> String? {
        try await self.systemProxyService.readActiveDisplay()
    }

    func isSystemProxyConfigured(host: String, ports: SystemProxyPorts) async throws -> Bool {
        try await self.systemProxyService.isConfigured(host: host, ports: ports)
    }

    func refreshSystemProxyHelperStatus() async {
        guard self.hasSystemProxyOpenIntent else {
            self.resetSystemProxyObservedState()
            return
        }
        let snapshot = await self.systemProxyService.readHelperHealthSnapshot()
        self.applyHelperHealthSnapshot(snapshot)
    }

    func refreshSystemProxyHelperRuntimeSnapshot() async {
        await self.refreshSystemProxyHelperStatus()
    }

    func refreshSystemProxyStatus() async {
        guard self.hasSystemProxyOpenIntent else {
            self.resetSystemProxyObservedState()
            return
        }

        do {
            let enabled = try await self.readSystemProxyEnabledState()
            self.isSystemProxyEnabled = enabled
            if enabled {
                self.systemProxyActiveDisplay = try await self.readSystemProxyActiveDisplay()
            } else {
                self.systemProxyActiveDisplay = nil
            }
            await self.refreshSystemProxyExceptionsFromSystemIfPossible()
            await self.refreshSystemProxyHelperRuntimeSnapshot()
            self.systemProxyHelperFailureReason = nil
            self.systemProxyHelperFailureMessage = nil
        } catch {
            self.appendLog(
                level: "error",
                message: tr("log.system_proxy.read_failed", self.systemProxyErrorMessage(error)))
            await self.refreshSystemProxyHelperStatus()
        }
    }

    func systemProxyPorts(from config: ConfigSnapshot) -> SystemProxyPorts {
        SystemProxyPorts.resolve(
            mixedPort: config.mixedPort,
            httpPort: config.port,
            socksPort: config.socksPort)
    }

    func toggleSystemProxy(_ enabled: Bool) async {
        self.isProxySyncing = true
        self.systemProxyEnableIntentInFlight = enabled
        self.clearSystemProxyOpenFailureHint()
        defer { self.isProxySyncing = false }
        defer { self.systemProxyEnableIntentInFlight = false }

        do {
            if enabled {
                let target = try await self.resolveSystemProxyTargetFromRuntimeConfig()
                try await self.applySystemProxy(enabled: true, host: target.host, ports: target.ports)
                try await self.applyCurrentSystemProxyExceptionsIfNeeded()
                self.systemProxyActiveDisplay = self.buildSystemProxyDisplayString(
                    host: target.host,
                    ports: target.ports)
            } else {
                let host = self.controllerHost
                try await self.applySystemProxy(enabled: false, host: host, ports: .disabled)
                self.systemProxyActiveDisplay = nil
            }

            self.isSystemProxyEnabled = enabled
            self.clearSystemProxyOpenFailureHint()
            self.systemProxyHelperFailureReason = nil
            self.systemProxyHelperFailureMessage = nil
            if enabled {
                await self.refreshSystemProxyHelperRuntimeSnapshot()
            } else {
                self.resetSystemProxyObservedState()
            }
            let state = enabled ? tr("log.system_proxy.enabled") : tr("log.system_proxy.disabled")
            self.appendLog(level: "info", message: tr("log.system_proxy.toggled", state))
        } catch {
            self.appendLog(
                level: "error",
                message: tr("log.system_proxy.toggle_failed", self.systemProxyErrorMessage(error)))
            self.updateSystemProxyOpenFailureHint(for: error)
            await self.refreshSystemProxyHelperStatus()
            await self.refreshSystemProxyStatus()
        }
    }

    func resolveSystemProxyTargetFromRuntimeConfig() async throws -> (host: String, ports: SystemProxyPorts) {
        let config = try await self.getRuntimeConfigSnapshot()
        let ports = self.systemProxyPorts(from: config)
        guard ports.hasEnabledPort else {
            throw SystemProxyServiceError.invalidPort
        }
        let host = self.controllerHost
        return (host: host, ports: ports)
    }

    func ensureSystemProxyConsistencyOnFirstLaunchIfNeeded() async {
        guard !self.didCheckSystemProxyConsistencyOnLaunch else { return }
        guard self.isRuntimeRunning else { return }
        guard self.hasSystemProxyOpenIntent else {
            self.resetSystemProxyObservedState()
            self.didCheckSystemProxyConsistencyOnLaunch = true
            return
        }
        guard self.isSystemProxyEnabled else {
            self.didCheckSystemProxyConsistencyOnLaunch = true
            return
        }

        do {
            let target = try await self.resolveSystemProxyTargetFromRuntimeConfig()
            let isConfigured = try await self.isSystemProxyConfigured(host: target.host, ports: target.ports)
            if !isConfigured {
                try await self.applySystemProxy(enabled: true, host: target.host, ports: target.ports)
                self.appendLog(
                    level: "info",
                    message: tr("log.system_proxy.startup_repaired", target.host, target.ports.primaryPort ?? 0))
            }
            try await self.applyCurrentSystemProxyExceptionsIfNeeded()
            self.clearSystemProxyOpenFailureHint()
            self.systemProxyHelperFailureReason = nil
            self.systemProxyHelperFailureMessage = nil
            self.systemProxyActiveDisplay = self.buildSystemProxyDisplayString(host: target.host, ports: target.ports)

            self.didCheckSystemProxyConsistencyOnLaunch = true
            await self.refreshSystemProxyStatus()
        } catch {
            self.appendLog(
                level: "error",
                message: tr("log.system_proxy.startup_repair_failed", self.systemProxyErrorMessage(error)))
            self.updateSystemProxyOpenFailureHint(for: error)
            await self.refreshSystemProxyHelperStatus()
        }
    }

    func scheduleSystemProxyStartupPostflight(
        refreshStatusBeforeOverlay: Bool,
        refreshStatusAfterBootstrap: Bool)
    {
        guard self.hasSystemProxyOpenIntent else {
            self.resetSystemProxyObservedState()
            return
        }
        let shouldRefreshStatus = refreshStatusBeforeOverlay || refreshStatusAfterBootstrap
        let shouldRepairConsistency = !self.didCheckSystemProxyConsistencyOnLaunch
        guard shouldRefreshStatus || shouldRepairConsistency else { return }

        Task { [weak self] in
            guard let self else { return }

            if shouldRefreshStatus {
                await self.refreshSystemProxyStatus()
            }

            if shouldRepairConsistency {
                await self.ensureSystemProxyConsistencyOnFirstLaunchIfNeeded()
                if shouldRefreshStatus {
                    await self.refreshSystemProxyStatus()
                }
            }
        }
    }

    func systemProxyErrorMessage(_ error: Error) -> String {
        guard let serviceError = error as? SystemProxyServiceError else { return error.localizedDescription }
        switch serviceError {
        case .invalidHost: return tr("app.system_proxy.error.invalid_host")
        case .invalidPort: return tr("app.system_proxy.error.invalid_port")
        case .helperNotBundled: return tr("app.system_proxy.error.helper_not_bundled")
        case .helperRequiresInstallToApplications: return tr("app.system_proxy.error.helper_install_location")
        case .helperNeedsApproval: return tr("app.system_proxy.error.helper_needs_approval")
        case .helperStartTimedOut: return tr("app.system_proxy.error.helper_start_timed_out")
        case let .helperNotRegistered(message):
            if let message, !message.isEmpty {
                return tr("app.system_proxy.error.helper_not_registered_with_detail", message)
            }
            return tr("app.system_proxy.error.helper_not_registered")
        case let .helperInvalidSignature(message): return tr("app.system_proxy.error.helper_invalid_signature", message)
        case let .helperConnectionFailed(message): return tr("app.system_proxy.error.helper_connection_failed", message)
        case let .helperOperationFailed(message): return tr("app.system_proxy.error.helper_operation_failed", message)
        }
    }

    func systemProxyFailureHintMessage(for error: Error) -> String {
        guard let serviceError = error as? SystemProxyServiceError else { return tr("app.system_proxy.alert.unknown") }
        switch serviceError {
        case .invalidHost: return tr("app.system_proxy.alert.invalid_host")
        case .invalidPort: return tr("app.system_proxy.alert.invalid_port")
        case .helperNotBundled: return tr("app.system_proxy.alert.helper_not_bundled")
        case .helperRequiresInstallToApplications: return tr("app.system_proxy.alert.helper_install_location")
        case .helperNeedsApproval: return tr("app.system_proxy.alert.background_activity_disabled")
        case .helperNotRegistered: return tr("app.system_proxy.alert.helper_not_registered")
        case .helperStartTimedOut: return tr("app.system_proxy.alert.helper_start_timed_out")
        case .helperInvalidSignature: return tr("app.system_proxy.alert.helper_invalid_signature")
        case .helperConnectionFailed: return tr("app.system_proxy.alert.helper_connection_failed")
        case .helperOperationFailed: return tr("app.system_proxy.alert.helper_operation_failed")
        }
    }

    private func systemProxyFailureReasonMessage(for reason: SystemProxyHelperFailureReason) -> String {
        switch reason {
        case .backgroundActivityDisabled: tr("app.system_proxy.alert.background_activity_disabled")
        case .helperNotRegistered: tr("app.system_proxy.alert.helper_not_registered")
        case .helperStartTimedOut: tr("app.system_proxy.alert.helper_start_timed_out")
        case .helperConnectionFailed: tr("app.system_proxy.alert.helper_connection_failed")
        case .helperOperationFailed: tr("app.system_proxy.alert.helper_operation_failed")
        case .appNotInApplications: tr("app.system_proxy.alert.helper_install_location")
        case .helperNotBundled: tr("app.system_proxy.alert.helper_not_bundled")
        case .signatureMismatch: tr("app.system_proxy.alert.helper_invalid_signature")
        case .unknown: tr("app.system_proxy.alert.unknown")
        }
    }

    private func normalizedSystemProxyComparisonHost(_ host: String) -> String {
        switch host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "localhost", "127.0.0.1", "0.0.0.0", "::1", "::", "0:0:0:0:0:0:0:0":
            "loopback"
        default:
            host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    func normalizedSystemProxyExceptionValues(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []

        for value in values {
            let trimmed = value.trimmed
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }

    func currentSystemProxyExceptionValues() -> [String] {
        self.normalizedSystemProxyExceptionValues(self.systemProxyExceptions.map(\.value))
    }

    private func systemProxyExceptionRows(from values: [String]) -> [EditableSystemProxyException] {
        self.normalizedSystemProxyExceptionValues(values).map { EditableSystemProxyException(value: $0) }
    }

    private func controllerHost(from value: String) -> String? {
        URLComponents(string: value.hasPrefix("http://") || value.hasPrefix("https://") ? value : "http://\(value)")?
            .host
    }

    func buildSystemProxyDisplayString(host: String, ports: SystemProxyPorts) -> String {
        let portDisplay = ports.primaryPort.map { String($0) } ?? "-"
        return "\(host):\(portDisplay)"
    }

    @discardableResult
    private func runSystemProxySettingsOperation(
        syncingKey: String,
        successMessage: String,
        operation: () async throws -> Void) async -> Bool
    {
        do {
            try await operation()
            await self.refreshSystemProxyHelperStatus()
            if self.hasSystemProxyOpenIntent {
                await self.refreshSystemProxyStatus()
            }
            return true
        } catch {
            self.appendLog(
                level: "error",
                message: tr(
                    "app.settings.error.save_failed",
                    tr("ui.section.system_proxy_exceptions"),
                    self.systemProxyErrorMessage(error)))
            await self.refreshSystemProxyHelperStatus()
            return false
        }
    }
}
