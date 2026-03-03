import Foundation

enum TunModeError: LocalizedError {
    case configNotSelected
    case runtimeStateMismatch(expected: Bool)

    var errorDescription: String? {
        switch self {
        case .configNotSelected:
            "No config file selected."
        case let .runtimeStateMismatch(expected):
            "TUN runtime state mismatch. expected=\(expected)"
        }
    }
}

@MainActor
extension AppState {
    func toggleTunMode(_ enabled: Bool) async {
        guard !isTunSyncing else { return }
        guard enabled != isTunEnabled else { return }

        isTunSyncing = true
        let previousValue = isTunEnabled
        defer { isTunSyncing = false }

        do {
            if enabled {
                try await self.ensureTunPermissions(requestIfMissing: true)
            }

            isTunEnabled = enabled
            persistEditableSettingsSnapshot()
            try await self.persistTunConfigToSelectedFile(enabled: enabled, ensureDNSEnabled: enabled)
            try await self.applyTunRuntimeChange(enabled: enabled)

            appendLog(
                level: "info",
                message: tr("log.tun.toggled", enabled ? tr("log.tun.enabled") : tr("log.tun.disabled")))
        } catch {
            isTunEnabled = previousValue
            persistEditableSettingsSnapshot()
            appendLog(level: "error", message: tr("log.tun.toggle_failed", self.tunErrorMessage(error)))
            await self.refreshTunStatusFromRuntimeConfig()
        }
    }

    func prepareTunOverlayForCoreStartup(
        configPath: String,
        overlay: EditableSettingsSnapshot) async throws -> EditableSettingsSnapshot
    {
        guard overlay.tunEnabled else { return overlay }

        do {
            // On app updates, bundled mihomo may lose setuid/root ownership.
            // Request permission proactively to avoid silently disabling TUN on startup.
            try await self.ensureTunPermissions(requestIfMissing: true)
            return overlay
        } catch {
            try tunConfigFileService.patchConfig(
                at: configPath,
                tunEnabled: false,
                ensureDNSEnabledWhenTunOn: false)
            isTunEnabled = false
            persistEditableSettingsSnapshot()
            appendLog(level: "warning", message: tr("log.tun.startup_disabled"))
            return overlay.withTunEnabled(false)
        }
    }

    func validateTunPermissionsOnStartup() async {
        guard isTunEnabled else { return }
        do {
            try await self.ensureTunPermissions(requestIfMissing: false)
        } catch {
            do {
                try? await self.persistTunConfigToSelectedFile(enabled: false, ensureDNSEnabled: false)
                if isRuntimeRunning {
                    try await self.patchTunConfig(enable: false)
                }
                isTunEnabled = false
                persistEditableSettingsSnapshot()
                appendLog(level: "warning", message: tr("log.tun.startup_disabled"))
            } catch {
                appendLog(level: "error", message: tr("log.tun.startup_check_failed", self.tunErrorMessage(error)))
            }
        }
    }

    func tunErrorMessage(_ error: Error) -> String {
        if let permissionError = error as? TunPermissionServiceError {
            switch permissionError {
            case .coreBinaryNotFound, .coreBinaryNotExecutable:
                return tr("app.tun.error.binary_not_found")
            case .permissionMissing:
                return tr("app.tun.error.permission_missing")
            case .authorizationCancelled:
                return tr("app.tun.error.authorization_cancelled")
            case let .authorizationFailed(message):
                return tr("app.tun.error.authorization_failed", message)
            case .permissionVerificationFailed:
                return tr("app.tun.error.permission_verify_failed")
            }
        }

        if let fileError = error as? TunConfigFileServiceError {
            switch fileError {
            case .configPathEmpty, .configNotFound, .unableToReadConfig:
                return tr("app.tun.error.config_unavailable")
            case let .unableToWriteConfig(message):
                return tr("app.tun.error.config_write_failed", message)
            }
        }

        if let tunModeError = error as? TunModeError {
            switch tunModeError {
            case .configNotSelected:
                return tr("app.tun.error.config_not_selected")
            case .runtimeStateMismatch:
                return tr("app.tun.error.runtime_state_mismatch")
            }
        }

        if let apiError = error as? APIError,
           case .statusCode = apiError
        {
            return tr("app.tun.error.patch_failed", apiError.localizedDescription)
        }

        return error.localizedDescription
    }

    func resolvedMihomoBinaryPath() -> String? {
        if let detected = processManager.detectedBinaryPath,
           !detected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return detected
        }

        let current = mihomoBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == "-" {
            return nil
        }
        return current
    }

    func ensureTunPermissions(requestIfMissing: Bool) async throws {
        guard let binaryPath = resolvedMihomoBinaryPath() else {
            throw TunPermissionServiceError.coreBinaryNotFound
        }

        do {
            try tunPermissionService.validateCurrentPermissions(binaryPath: binaryPath)
        } catch TunPermissionServiceError.permissionMissing {
            guard requestIfMissing else {
                throw TunPermissionServiceError.permissionMissing
            }
            appendLog(level: "info", message: tr("log.tun.permission_requesting"))
            try await tunPermissionService.grantPermissions(binaryPath: binaryPath)
            appendLog(level: "info", message: tr("log.tun.permission_granted"))
        }
    }

    func persistTunConfigToSelectedFile(enabled: Bool, ensureDNSEnabled: Bool) async throws {
        guard let configPath = await resolveSelectedConfigPath() else {
            throw TunModeError.configNotSelected
        }
        try tunConfigFileService.patchConfig(
            at: configPath,
            tunEnabled: enabled,
            ensureDNSEnabledWhenTunOn: ensureDNSEnabled)
    }

    func applyTunRuntimeChange(enabled: Bool) async throws {
        guard isRuntimeRunning else { return }
        await restartCore(trigger: .restart)
        try await self.verifyTunRuntimeState(expectedEnabled: enabled)
    }

    func verifyTunRuntimeState(expectedEnabled: Bool) async throws {
        let maxAttempts = 15
        for _ in 0..<maxAttempts {
            do {
                let config = try await fetchRuntimeConfigSnapshot()
                let current = config.tunEnabled ?? false
                isTunEnabled = current
                if current == expectedEnabled {
                    return
                }
            } catch {
                // Ignore transient API failures while core is restarting.
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        throw TunModeError.runtimeStateMismatch(expected: expectedEnabled)
    }

    func patchTunConfig(enable: Bool) async throws {
        let client = try clientOrThrow()
        var body: [String: JSONValue] = [
            "tun": .object(["enable": .bool(enable)]),
        ]
        if enable {
            body["dns"] = .object(["enable": .bool(true)])
        }
        try await client.requestNoResponse(.patchConfigs(body: body))
    }

    func refreshTunStatusFromRuntimeConfig() async {
        do {
            let config = try await fetchRuntimeConfigSnapshot()
            if let tunEnabled = config.tunEnabled {
                isTunEnabled = tunEnabled
            }
        } catch {
            // Keep current UI state when runtime config refresh is unavailable.
        }
    }
}
