import Foundation
import MihomoKit

enum TunModeError: LocalizedError {
    case runtimeStateMismatch(expected: Bool)

    var errorDescription: String? {
        switch self {
        case let .runtimeStateMismatch(expected):
            "TUN runtime state mismatch. expected=\(expected)"
        }
    }
}

@MainActor
extension ProxyStore {
    func toggleTunMode(_ enabled: Bool) async {
        guard !self.isTunSyncing else { return }
        guard enabled != self.tunEnabled else { return }

        self.isTunSyncing = true
        defer { self.isTunSyncing = false }

        do {
            if enabled, !self.isRemoteTarget {
                try await self.ensureTunPermissions(requestIfMissing: true)
            }

            guard self.isRemoteTarget || self.isRuntimeRunning else { return }
            try await self.patchTunConfig(enable: enabled)

            let config = try await self.getRuntimeConfigSnapshot()
            let actualState = config.tunEnabled ?? false
            self.tunEnabled = actualState

            if actualState == enabled {
                self.appendLog(
                    level: "info",
                    message: tr("log.tun.toggled", enabled ? tr("log.tun.enabled") : tr("log.tun.disabled")))
            } else {
                self.appendLog(
                    level: "error",
                    message: tr("log.tun.toggle_failed", tr("app.tun.error.runtime_state_mismatch")))
            }
        } catch {
            self.appendLog(level: "error", message: tr("log.tun.toggle_failed", self.tunErrorMessage(error)))
            await self.refreshTunStatusFromRuntimeConfig()
        }
    }

    func prepareTunOverlayForCoreStartup(_ overlay: EditableSettingsSnapshot) async throws -> EditableSettingsSnapshot {
        guard overlay.tunEnabled else { return overlay }

        do {
            try await self.ensureTunPermissions(requestIfMissing: true)
            return overlay
        } catch {
            self.tunEnabled = false
            self.appendLog(level: "warning", message: tr("log.tun.startup_disabled"))
            return overlay.withTunEnabled(false)
        }
    }

    func validateTunPermissionsOnStartup() async {
        guard self.tunEnabled else { return }
        do {
            try await self.ensureTunPermissions(requestIfMissing: false)
        } catch {
            if self.isRuntimeRunning {
                try? await self.patchTunConfig(enable: false)
            }
            self.tunEnabled = false
            self.appendLog(level: "warning", message: tr("log.tun.startup_disabled"))
        }
    }

    func tunErrorMessage(_ error: Error) -> String {
        if let permissionError = error as? TunPermissionServiceError {
            switch permissionError {
            case .coreBinaryNotFound, .coreBinaryNotExecutable:
                let corePath = self.coreDirectoryURL.path
                return tr("app.tun.error.binary_not_found", corePath)
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

        if let tunModeError = error as? TunModeError {
            switch tunModeError {
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

    func ensureTunPermissions(requestIfMissing: Bool) async throws {
        guard let binaryPath = self.resolvedBinaryPath else {
            throw TunPermissionServiceError.coreBinaryNotFound
        }

        do {
            try self.tunPermissionService.validateCurrentPermissions(binaryPath: binaryPath)
        } catch TunPermissionServiceError.permissionMissing {
            guard requestIfMissing else {
                throw TunPermissionServiceError.permissionMissing
            }
            self.appendLog(level: "info", message: tr("log.tun.permission_requesting"))
            try await self.tunPermissionService.grantPermissions(binaryPath: binaryPath)
            self.appendLog(level: "info", message: tr("log.tun.permission_granted"))
        }
    }

    func verifyTunAfterOverlayIfNeeded(overlay: EditableSettingsSnapshot) async {
        guard overlay.tunEnabled, self.isRuntimeRunning else { return }
        guard self.pendingCoreFeatureRecoveryState == nil else { return }

        do {
            let config = try await self.getRuntimeConfigSnapshot()
            if config.tunEnabled == true {
                self.tunEnabled = true
                return
            }

            try await self.patchTunConfig(enable: true)
            try await self.verifyTunRuntimeState(expectedEnabled: true)
            self.tunEnabled = true
            self.appendLog(level: "info", message: tr("log.tun.toggled", tr("log.tun.enabled")))
        } catch {
            self.appendLog(level: "error", message: tr("log.tun.toggle_failed", self.tunErrorMessage(error)))
        }
    }

    func applyTunRuntimeChange(enabled: Bool) async throws {
        guard self.isRemoteTarget || self.isRuntimeRunning else { return }
        try await self.patchTunConfig(enable: enabled)
        try await self.verifyTunRuntimeState(expectedEnabled: enabled)
    }

    func verifyTunRuntimeState(expectedEnabled: Bool) async throws {
        let config = try await self.getRuntimeConfigSnapshot()
        let actual = config.tunEnabled ?? false
        if actual != expectedEnabled {
            throw TunModeError.runtimeStateMismatch(expected: expectedEnabled)
        }
    }

    func patchTunConfig(enable: Bool) async throws {
        let client = try self.resolveClient()
        var tunBody: [String: JSONValue] = ["enable": .bool(enable)]

        if enable, !self.selectedConfigDeclaresTunStack() {
            tunBody["stack"] = .string("mixed")
        }

        var body: [String: JSONValue] = ["tun": .object(tunBody)]
        if enable {
            body["dns"] = .object(["enable": .bool(true)])
        }
        try await client.requestNoResponse(.patchConfigs(body: body))
    }

    func ensureTunMixedStackOnStartupIfNeeded() async {
        guard self.isRuntimeRunning else { return }

        do {
            let config = try await self.getRuntimeConfigSnapshot()
            guard config.tunEnabled == true else { return }
            let hasConfiguredStack = self.selectedConfigDeclaresTunStack()

            let client = try self.resolveClient()
            var body: [String: JSONValue] = [
                "dns": .object(["enable": .bool(true)]),
            ]
            if !hasConfiguredStack {
                body["tun"] = .object(["stack": .string("mixed")])
            }
            try await client.requestNoResponse(.patchConfigs(body: body))
            if !hasConfiguredStack {
                _ = try await self.getRuntimeConfigSnapshot()
            }
        } catch {
            self.appendLog(level: "error", message: tr("log.tun.startup_check_failed", self.tunErrorMessage(error)))
        }
    }

    func refreshTunStatusFromRuntimeConfig() async {
        do {
            let config = try await self.getRuntimeConfigSnapshot()
            if let tunEnabled = config.tunEnabled, self.tunEnabled != tunEnabled {
                self.tunEnabled = tunEnabled
            }
        } catch {}
    }

    func selectedConfigDeclaresTunStack() -> Bool {
        guard
            let configPath = self.selectedConfigPath,
            let raw = try? String(contentsOfFile: configPath, encoding: .utf8)
        else {
            return false
        }

        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let tunRange = self.topLevelBlockRange(for: "tun", lines: lines) else { return false }
        return self.childLineExists(for: "stack", lines: lines, range: tunRange)
    }

    private func childLineExists(for key: String, lines: [String], range: Range<Int>) -> Bool {
        for index in (range.lowerBound + 1)..<range.upperBound {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.count
            guard leadingSpaces > 0 else { continue }

            let content = String(line.dropFirst(leadingSpaces)).trimmingCharacters(in: .whitespaces)
            if content == "\(key):" || content.hasPrefix("\(key): ") {
                return true
            }
        }
        return false
    }

    private func topLevelBlockRange(for key: String, lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { self.isTopLevelKeyLine($0, key: key) }) else {
            return nil
        }

        var end = lines.count
        if start + 1 < lines.count {
            for index in (start + 1)..<lines.count where self.isTopLevelMappingLine(lines[index]) {
                end = index
                break
            }
        }
        return start..<end
    }

    private func isTopLevelKeyLine(_ line: String, key: String) -> Bool {
        guard line.prefix(while: { $0 == " " || $0 == "\t" }).isEmpty else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        return trimmed == "\(key):" || trimmed.hasPrefix("\(key): ")
    }

    private func isTopLevelMappingLine(_ line: String) -> Bool {
        guard line.prefix(while: { $0 == " " || $0 == "\t" }).isEmpty else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        return trimmed.contains(":")
    }
}
