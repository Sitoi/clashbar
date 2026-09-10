import Combine
import Foundation
import MihomoKit

@MainActor
final class SettingsStore: ObservableObject {
    @Published var editableSettings = EditableSettingsSnapshot() {
        didSet {
            if !self.suppressSettingsPersistence {
                self.persistEditableSettingsSnapshot()
            }
        }
    }

    @Published var settingsSyncingKey: String?
    var isCoreSettingSyncing: Bool {
        self.settingsSyncingKey != nil
    }

    @Published var settingsErrorMessage: String?
    @Published var settingsSavedMessage: String?

    var lastSyncedEditableSettings: EditableSettingsSnapshot?
    var preserveLocalSettingsOnNextSync = false
    var suppressSettingsPersistence = false

    var apiClientProvider: (() throws -> MihomoAPIService)?
    var logHandler: ((_ level: String, _ message: String) -> Void)?
    var onPortsChanged: (() async -> Void)?

    private let defaults: UserDefaults
    private let editableSettingsSnapshotKey = "clashbar.settings.editable.snapshot.v1"

    private var proxyPortsAutoSaveTask: Task<Void, Never>?
    private var settingsFeedbackClearTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.loadPersistedSettings()
    }

    func loadPersistedSettings() {
        self.suppressSettingsPersistence = true
        defer { self.suppressSettingsPersistence = false }

        if let data = self.defaults.data(forKey: self.editableSettingsSnapshotKey),
           let snapshot = try? JSONDecoder().decode(EditableSettingsSnapshot.self, from: data)
        {
            self.editableSettings = snapshot
        }
    }

    func persistEditableSettingsSnapshot() {
        guard !self.suppressSettingsPersistence else { return }
        if let data = try? JSONEncoder().encode(self.editableSettings) {
            self.defaults.set(data, forKey: self.editableSettingsSnapshotKey)
        }
    }

    func effectiveMixedPort() -> Int {
        if let value = Int(self.editableSettings.mixedPort.trimmed), (1...65535).contains(value) {
            return value
        }
        return 7890
    }

    func applyEditableCoreSetting(_ setting: EditableBooleanSetting, to value: Bool) async {
        await self.patchSingleConfig(setting.rawValue, value: .bool(value))
    }

    func applyLogLevel(_ level: ConfigLogLevel) async {
        await self.patchSingleConfig("log-level", value: .string(level.rawValue))
    }

    func applyProxyPorts(autoSaved: Bool = false) async {
        guard let body = self.validatedPortPatchBody(
            fields: self.editableSettings.portFields(),
            skipEmptyValues: false)
        else { return }

        let syncingKey = autoSaved ? "ports-auto" : "ports"
        let successMessage = autoSaved ? "Ports auto-saved" : "Ports saved"
        let success = await self.patchConfigBody(body, syncingKey: syncingKey, successMessage: successMessage)
        if success {
            await self.onPortsChanged?()
        }
    }

    func scheduleProxyPortsAutoSaveIfNeeded() {
        guard !self.suppressSettingsPersistence else { return }
        guard self.settingsSyncingKey == nil else { return }

        self.proxyPortsAutoSaveTask?.cancel()
        self.proxyPortsAutoSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            self.proxyPortsAutoSaveTask = nil
            await self.applyProxyPorts(autoSaved: true)
        }
    }

    func cancelProxyPortsAutoSave() {
        self.proxyPortsAutoSaveTask?.cancel()
        self.proxyPortsAutoSaveTask = nil
    }

    func syncEditableSettings(from config: ConfigSnapshot) {
        let incoming = EditableSettingsSnapshot(config: config)

        if self.preserveLocalSettingsOnNextSync {
            self.preserveLocalSettingsOnNextSync = false
            self.lastSyncedEditableSettings = incoming
            self.persistEditableSettingsSnapshot()
            return
        }

        guard let previous = self.lastSyncedEditableSettings else {
            self.applyEditableSettingsSnapshotToUI(incoming)
            self.lastSyncedEditableSettings = incoming
            self.persistEditableSettingsSnapshot()
            return
        }

        self.suppressSettingsPersistence = true
        self.editableSettings.mergeRuntimeChanges(from: previous, to: incoming)
        self.suppressSettingsPersistence = false

        self.lastSyncedEditableSettings = incoming
        self.persistEditableSettingsSnapshot()
    }

    func applyEditableSettingsSnapshotToUI(_ snapshot: EditableSettingsSnapshot) {
        self.suppressSettingsPersistence = true
        self.editableSettings = snapshot
        self.suppressSettingsPersistence = false
    }

    func patchSingleConfig(_ key: String, value: JSONValue) async {
        _ = await self.patchConfigBody(
            [key: value],
            syncingKey: key,
            successMessage: "Config [\(key)] saved")
    }

    @discardableResult
    func patchConfigBody(
        _ body: [String: JSONValue],
        syncingKey: String,
        successMessage: String) async -> Bool
    {
        self.cancelProxyPortsAutoSave()
        self.settingsFeedbackClearTask?.cancel()
        self.settingsFeedbackClearTask = nil
        self.settingsSyncingKey = syncingKey
        self.settingsErrorMessage = nil
        self.settingsSavedMessage = nil
        defer { self.settingsSyncingKey = nil }

        let patchKeysDescription = body.keys.sorted().joined(separator: ", ")
        do {
            let client = try self.resolveClient()
            self.logHandler?("info", "PATCH /configs [\(patchKeysDescription)]")
            try await client.requestNoResponse(.patchConfigs(body: body))
            self.logHandler?("info", "PATCH /configs succeeded [\(patchKeysDescription)]")
            await self.reconcileEditableSettingsWithRuntimeConfig()
            self.settingsSavedMessage = successMessage
            self.scheduleSettingsFeedbackAutoClearIfNeeded(message: successMessage)
            return true
        } catch {
            self.logHandler?("error", "PATCH /configs failed [\(patchKeysDescription)]: \(error.localizedDescription)")
            self.settingsErrorMessage = "Failed to save: \(error.localizedDescription)"
            self.settingsSavedMessage = nil
            await self.reconcileEditableSettingsWithRuntimeConfig()
            return false
        }
    }

    func reconcileEditableSettingsWithRuntimeConfig() async {
        do {
            let client = try self.resolveClient()
            let config: ConfigSnapshot = try await client.request(.getConfigs)
            let incoming = EditableSettingsSnapshot(config: config)
            self.applyEditableSettingsSnapshotToUI(incoming)
            self.lastSyncedEditableSettings = incoming
            self.persistEditableSettingsSnapshot()
        } catch {
            self.logHandler?("error", "Settings reconciliation failed: \(error.localizedDescription)")
        }
    }

    private func validatedPortPatchBody(
        fields: [SettingsPortField],
        skipEmptyValues: Bool) -> [String: JSONValue]?
    {
        var body: [String: JSONValue] = [:]
        for field in fields {
            let trimmed = field.value.trimmed
            if trimmed.isEmpty {
                if !skipEmptyValues {
                    body[field.key] = .int(0)
                }
                continue
            }
            guard let port = Int(trimmed), (0...65535).contains(port) else {
                self.settingsErrorMessage = "Port out of range (0-65535)"
                return nil
            }
            body[field.key] = .int(port)
        }
        return body
    }

    func scheduleSettingsFeedbackAutoClearIfNeeded(message: String) {
        self.settingsFeedbackClearTask?.cancel()
        self.settingsFeedbackClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            if self.settingsSavedMessage == message {
                self.settingsSavedMessage = nil
            }
            self.settingsFeedbackClearTask = nil
        }
    }

    private func resolveClient() throws -> MihomoAPIService {
        guard let provider = self.apiClientProvider else {
            throw APIError.clientUnavailable
        }
        return try provider()
    }
}
