import AppKit
import Combine
import Foundation
import MihomoKit
import UniformTypeIdentifiers

/// Configuration preferences, repository and subscription work shared by the app's entry points.
@MainActor
final class ConfigurationStore: ObservableObject {
    var subscriptions: [String: RemoteConfigSubscription] = [:]
    @Published var remoteConfigMenuStates: [String: RemoteConfigMenuState] = [:]

    @Published var selectedConfigName: String = "-"
    @Published var availableConfigFileNames: [String] = []
    @Published var configDirectoryPath: String = "-"
    @Published var ssidStrategyRules: [SSIDStrategyRule] = []
    @Published var ssidStrategyCurrentSSID: String?
    @Published var ssidStrategyAuthorizationStatus: SSIDMonitorAuthorizationStatus = .notDetermined
    @Published var ssidStrategyEnabled: Bool = false {
        didSet {
            self.defaults.set(self.ssidStrategyEnabled, forKey: "clashbar.ssid.strategy.enabled")
            if self.ssidStrategyEnabled {
                self.applySSIDStrategy(currentSSID: self.ssidStrategyCurrentSSID)
            }
        }
    }

    let workingDirectoryManager: WorkingDirectoryManager
    let configurationObserver = ConfigurationDirectoryObserver()
    private let defaults: UserDefaults

    private(set) var configDirectory: URL?
    private(set) var availableConfigs: [URL] = []
    private(set) var selectedConfig: URL?

    var onConfigSelected: ((_ configURL: URL) async -> Void)?
    var onConfigRestartRequired: (() async -> Void)?
    var logHandler: ((_ level: String, _ message: String) -> Void)?
    var userAgentProvider: (() async -> String)?
    var validateConfigBeforeSwitch: ((_ path: String) async -> Bool)?

    private let selectedConfigKey = "clashbar.config.selected.filename"
    private let legacySelectedConfigKey = "clashbar.config.selected"
    private let remoteConfigSourcesKey = "clashbar.config.remote.sources.v1"
    private let remoteConfigSubscriptionsKey = "clashbar.config.remote.subscriptions.v2"
    private let lastSuccessfulConfigPathKey = "clashbar.last.success.config.path"
    private let ssidStrategyRulesKey = "clashbar.ssid.strategy.rules.v1"
    private var automaticUpdateTask: Task<Void, Never>?
    private var menuRefreshTask: Task<Void, Never>?
    private let maxRemoteConfigBytes = 5 * 1024 * 1024

    init(
        workingDirectoryManager: WorkingDirectoryManager = WorkingDirectoryManager(),
        defaults: UserDefaults = .standard)
    {
        self.workingDirectoryManager = workingDirectoryManager
        self.defaults = defaults
        self.ssidStrategyEnabled = defaults.bool(forKey: "clashbar.ssid.strategy.enabled")
        self.ssidStrategyRules = self.loadSSIDStrategyRules()
        self.subscriptions = self.loadSubscriptions()
        _ = self.chooseConfigDirectory()
        _ = self.resolveSelectedConfig()
    }

    func chooseConfigDirectory() -> URL? {
        do {
            try self.workingDirectoryManager.bootstrapDirectories()
            let target = try self.workingDirectoryManager.normalizeAndValidateWithinRoot(
                self.workingDirectoryManager.configDirectoryURL,
                mustBeDirectory: true)
            self.configDirectory = target
            self.configDirectoryPath = target.path
            self.reloadConfigs()
            return target
        } catch {
            return nil
        }
    }

    func setConfigDirectory(_ url: URL) {
        guard let safeURL = try? self.workingDirectoryManager.normalizeAndValidateWithinRoot(
            url,
            mustBeDirectory: true),
            safeURL == self.workingDirectoryManager.configDirectoryURL.standardizedFileURL
        else {
            return
        }
        self.configDirectory = safeURL
        self.configDirectoryPath = safeURL.path
        self.reloadConfigs()
    }

    func selectConfig(_ url: URL) {
        guard let configDirectory else { return }
        let safeConfig = try? self.workingDirectoryManager.normalizeAndValidateWithinRoot(url, mustBeDirectory: false)
        guard let safeConfig,
              safeConfig.deletingLastPathComponent() == configDirectory,
              ["yaml", "yml"].contains(safeConfig.pathExtension.lowercased())
        else {
            return
        }
        self.selectedConfig = safeConfig
        self.selectedConfigName = safeConfig.lastPathComponent
        self.rememberSelection(named: safeConfig.lastPathComponent)
    }

    @discardableResult
    func reloadConfigs() -> [URL] {
        guard let configDirectory else {
            self.applyScannedConfigs([])
            return []
        }

        let files = Self.scanConfigFiles(in: configDirectory)
        self.applyScannedConfigs(files)
        return files
    }

    func applyScannedConfigs(_ files: [URL]) {
        self.availableConfigs = files
        self.availableConfigFileNames = files.map(\.lastPathComponent)
        if let selectedConfig, files.contains(selectedConfig) {
            self.selectedConfigName = selectedConfig.lastPathComponent
            return
        }
        if let first = files.first {
            self.selectedConfig = first
            self.selectedConfigName = first.lastPathComponent
        } else {
            self.selectedConfig = nil
            self.selectedConfigName = "-"
        }
    }

    nonisolated static func scanConfigFiles(in directory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])) ?? []

        return children.filter { fileURL in
            let resolved = fileURL.resolvingSymlinksInPath()
            let isRegularFile = (try? resolved.resourceValues(forKeys: keys).isRegularFile) ?? false
            let fileExtension = fileURL.pathExtension.lowercased()
            return isRegularFile && (fileExtension == "yaml" || fileExtension == "yml")
        }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    func resolveSelectedConfig() -> URL? {
        if let selected = self.selectedConfig {
            return selected
        }
        if let name = self.defaults.string(forKey: self.selectedConfigKey),
           let selected = self.availableConfigs.first(where: { $0.lastPathComponent == name })
        {
            self.selectConfig(selected)
            return selected
        }
        if let legacyPath = self.defaults.string(forKey: self.legacySelectedConfigKey) {
            let name = URL(fileURLWithPath: legacyPath).lastPathComponent
            self.rememberSelection(named: name)
            self.defaults.removeObject(forKey: self.legacySelectedConfigKey)
            if let selected = self.availableConfigs.first(where: { $0.lastPathComponent == name }) {
                self.selectConfig(selected)
                return selected
            }
        }
        self.reloadConfigs()
        return self.selectedConfig
    }

    func rememberSelection(named fileName: String?) {
        if let fileName {
            self.defaults.set(fileName, forKey: self.selectedConfigKey)
        } else {
            self.defaults.removeObject(forKey: self.selectedConfigKey)
        }
    }

    func rememberSuccessfulConfig(path: String) {
        self.defaults.set(path, forKey: self.lastSuccessfulConfigPathKey)
    }

    func restoreLastSuccessfulConfig() -> URL? {
        guard let path = self.defaults.string(forKey: self.lastSuccessfulConfigPathKey), !path.isEmpty
        else { return nil }
        let candidate = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        guard let matched = self.availableConfigs.first(where: {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
                == candidate.standardizedFileURL.resolvingSymlinksInPath().path
        }) else { return nil }
        self.selectConfig(matched)
        return matched
    }

    func selectConfigFile(named fileName: String) async {
        guard let matched = self.availableConfigs.first(where: { $0.lastPathComponent == fileName }) else {
            self.logHandler?("error", "Config not found: \(fileName)")
            return
        }

        if let validator = self.validateConfigBeforeSwitch {
            let isValid = await validator(matched.path)
            guard isValid else { return }
        }

        self.selectConfig(matched)
        self.logHandler?("info", "Selected config: \(fileName)")
        await self.onConfigSelected?(matched)
    }

    func seedBundledConfigIfNeeded() {
        let fileManager = FileManager.default
        let targetURL = self.workingDirectoryManager.configDirectoryURL
            .appendingPathComponent("ClashBar.yaml", isDirectory: false)

        if fileManager.fileExists(atPath: targetURL.path) {
            return
        }

        guard let bundledConfigURL = AppResourceBundleLocator.bundledDefaultConfigURL(fileManager: fileManager) else {
            return
        }

        do {
            let data = try Data(contentsOf: bundledConfigURL)
            try self.writeConfigData(data, to: targetURL)
            self.reloadConfigs()
            self.logHandler?("info", "Seeded default ClashBar.yaml")
        } catch {
            self.logHandler?("error", "Failed to seed bundled config: \(error.localizedDescription)")
        }
    }

    func deleteConfigFile(named fileName: String) async {
        guard let configDirectory else { return }
        let targetURL = configDirectory.appendingPathComponent(fileName, isDirectory: false)
        do {
            try FileManager.default.removeItem(at: targetURL)
            self.removeRemoteConfigSubscription(for: fileName)
            self.reloadConfigs()
            self.logHandler?("info", "Deleted config: \(fileName)")
        } catch {
            self.logHandler?("error", "Delete config failed: \(error.localizedDescription)")
        }
    }

    func showSelectedConfigInFinder() {
        guard let url = self.selectedConfig else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func importLocalConfigFile() {
        guard let configDirectory = self.configDirectory else { return }

        let panel = NSOpenPanel()
        panel.title = "Import Local Config"
        panel.directoryURL = configDirectory
        var allowedTypes: [UTType] = []
        if let yamlType = UTType(filenameExtension: "yaml") {
            allowedTypes.append(yamlType)
        }
        if let ymlType = UTType(filenameExtension: "yml"), !allowedTypes.contains(ymlType) {
            allowedTypes.append(ymlType)
        }
        if !allowedTypes.isEmpty {
            panel.allowedContentTypes = allowedTypes
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        guard let fileName = self.normalizedConfigFileName(sourceURL.lastPathComponent) else {
            self.logHandler?("error", "Invalid config file name: \(sourceURL.lastPathComponent)")
            return
        }

        let targetURL = configDirectory.appendingPathComponent(fileName, isDirectory: false)
        do {
            let data = try Data(contentsOf: sourceURL)
            try self.writeConfigData(data, to: targetURL)
            self.removeRemoteConfigSubscription(for: fileName)
            self.reloadConfigs()
            self.logHandler?("info", "Imported local config: \(fileName)")
        } catch {
            self.logHandler?("error", "Import config failed: \(error.localizedDescription)")
        }
    }

    func updateAllRemoteConfigFiles() async {
        let subscriptions = self.subscriptions
        guard !subscriptions.isEmpty else {
            self.logHandler?("info", "No remote subscriptions to update")
            return
        }

        let userAgent = await self.userAgentProvider?()
        for fileName in subscriptions.keys.sorted() {
            await self.refreshRemoteConfigFile(named: fileName, userAgent: userAgent)
        }
    }

    func refreshRemoteConfigFile(named fileName: String, userAgent: String? = nil) async {
        guard let subscription = self.subscriptions[fileName],
              let remoteURL = URL(string: subscription.urlString),
              let configDirectory = self.configDirectory
        else { return }

        self.setRemoteConfigMenuState(for: fileName, phase: .refreshing)
        let defaultUA = await self.userAgentProvider?()
        let resolvedUA = userAgent ?? defaultUA

        do {
            let data = try await self.downloadRemoteConfigData(from: remoteURL, userAgent: resolvedUA)
            let targetURL = configDirectory.appendingPathComponent(fileName, isDirectory: false)
            try self.writeConfigData(data, to: targetURL)

            let updatedSub = subscription.markChecked(at: Date())
            self.upsertRemoteConfigSubscription(for: fileName, subscription: updatedSub)
            self.setRemoteConfigMenuState(for: fileName, phase: .idle, updatedAt: Date())
            self.logHandler?("info", "Remote config [\(fileName)] updated")

            if self.selectedConfigName == fileName {
                await self.onConfigRestartRequired?()
            }
        } catch {
            self.setRemoteConfigMenuState(for: fileName, phase: .failed)
            self.logHandler?("error", "Failed to update remote config [\(fileName)]: \(error.localizedDescription)")
        }
    }

    func loadSSIDStrategyRules() -> [SSIDStrategyRule] {
        SSIDStrategyRule.normalized(self.decode([SSIDStrategyRule].self, key: self.ssidStrategyRulesKey) ?? [])
    }

    func persistSSIDStrategyRules(_ rules: [SSIDStrategyRule]) {
        self.encode(SSIDStrategyRule.normalized(rules), key: self.ssidStrategyRulesKey)
    }

    func applySSIDStrategy(currentSSID: String?) {
        self.ssidStrategyCurrentSSID = currentSSID
        guard self.ssidStrategyEnabled, let currentSSID = currentSSID?.trimmedNonEmpty else { return }
        guard let rule = self.ssidStrategyRules
            .first(where: { $0.ssid.caseInsensitiveCompare(currentSSID) == .orderedSame }) else { return }
        Task { [weak self] in
            await self?.selectConfigFile(named: rule.configFileName)
        }
    }

    func toggleCurrentSSIDBinding(for configFileName: String) {
        let normalizedConfigFileName = configFileName.trimmed
        guard !normalizedConfigFileName.isEmpty,
              let currentSSID = self.ssidStrategyCurrentSSID?.trimmedNonEmpty else { return }

        if self.ssidStrategyRules
            .contains(where: { $0.ssid == currentSSID && $0.configFileName == normalizedConfigFileName })
        {
            self.removeSSIDStrategyBinding(ssid: currentSSID)
            return
        }

        var next = self.ssidStrategyRules.filter { $0.ssid.caseInsensitiveCompare(currentSSID) != .orderedSame }
        next.append(SSIDStrategyRule(ssid: currentSSID, configFileName: normalizedConfigFileName))
        self.ssidStrategyRules = next
        self.persistSSIDStrategyRules(next)
        self.logHandler?("info", "Bound SSID [\(currentSSID)] to [\(normalizedConfigFileName)]")
    }

    func removeSSIDStrategyBinding(ssid: String) {
        let normalizedSSID = ssid.trimmed
        guard !normalizedSSID.isEmpty else { return }
        let next = self.ssidStrategyRules.filter { $0.ssid.caseInsensitiveCompare(normalizedSSID) != .orderedSame }
        self.ssidStrategyRules = next
        self.persistSSIDStrategyRules(next)
        self.logHandler?("info", "Unbound SSID [\(normalizedSSID)]")
    }

    func startConfigMonitoring() {
        guard !self.configurationObserver.isMonitoring, let directoryURL = self.configDirectory else { return }
        self.reloadConfigs()
        self.configurationObserver.start(
            directoryURL: directoryURL,
            files: self.availableConfigs,
            selectedFileURL: self.selectedConfig)
        { [weak self] in
            await self?.handleConfigDirectoryChanges()
        }
    }

    func stopConfigMonitoring() {
        self.configurationObserver.stop()
    }

    private func handleConfigDirectoryChanges() async {
        guard let directoryURL = self.configDirectory else { return }
        let previousSelectedPath = self.selectedConfig?.path
        guard let changes = await self.configurationObserver.scanChanges(in: directoryURL) else { return }
        if !changes.fileNames.isEmpty {
            self.applyScannedConfigs(changes.files)
            self.configurationObserver.updateSelectedFile(self.selectedConfig)
            if let previousSelectedPath, let newSelected = self.selectedConfig,
               previousSelectedPath == newSelected.path
            {
                await self.onConfigRestartRequired?()
            }
        }
    }

    func loadSubscriptions() -> [String: RemoteConfigSubscription] {
        if let subscriptions = self.decode(
            [String: RemoteConfigSubscription].self,
            key: self.remoteConfigSubscriptionsKey)
        {
            return subscriptions.filter { fileName, subscription in
                self.isValidFileName(fileName)
                    && URL(string: subscription.urlString).map(self.isSupportedRemoteConfigURL) == true
            }
        }

        let sources = self.defaults.dictionary(forKey: self.remoteConfigSourcesKey) as? [String: String] ?? [:]
        var migrated: [String: RemoteConfigSubscription] = [:]
        for (fileName, urlString) in sources {
            guard self.isValidFileName(fileName),
                  let url = URL(string: urlString), self.isSupportedRemoteConfigURL(url)
            else { continue }
            migrated[fileName] = RemoteConfigSubscription(urlString: url.absoluteString)
        }
        guard !migrated.isEmpty else { return [:] }
        self.encode(migrated, key: self.remoteConfigSubscriptionsKey)
        self.defaults.removeObject(forKey: self.remoteConfigSourcesKey)
        return migrated
    }

    func persistSubscriptions() {
        self.encode(self.subscriptions, key: self.remoteConfigSubscriptionsKey)
    }

    func upsertRemoteConfigSubscription(for fileName: String, subscription: RemoteConfigSubscription) {
        self.subscriptions[fileName] = subscription
        self.persistSubscriptions()
    }

    func removeRemoteConfigSubscription(for fileName: String) {
        self.subscriptions.removeValue(forKey: fileName)
        self.remoteConfigMenuStates.removeValue(forKey: fileName)
        self.persistSubscriptions()
    }

    @discardableResult
    func pruneSubscriptions(availableFileNames: [String]) -> Bool {
        let validNames = Set(availableFileNames.map(\.trimmed))
        let filtered = self.subscriptions.filter { validNames.contains($0.key.trimmed) }
        guard filtered.count != self.subscriptions.count else { return false }
        self.subscriptions = filtered
        self.persistSubscriptions()
        return true
    }

    func remoteConfigMenuState(for fileName: String) -> RemoteConfigMenuState {
        self.remoteConfigMenuStates[fileName] ?? .idle
    }

    func setRemoteConfigMenuState(
        for fileName: String,
        phase: RemoteConfigRefreshPhase,
        updatedAt: Date? = nil)
    {
        let existing = self.remoteConfigMenuStates[fileName]
        let sub = self.subscriptions[fileName]
        let resolvedUpdatedAt = updatedAt ?? existing?.updatedAt
        self.remoteConfigMenuStates[fileName] = RemoteConfigMenuState(
            updatedAt: resolvedUpdatedAt,
            phase: phase,
            autoUpdateEnabled: sub?.autoUpdateEnabled ?? false,
            nextUpdateAt: sub?.nextUpdateAt())
    }

    func writeConfigData(_ data: Data, to targetURL: URL) throws {
        guard !data.isEmpty else {
            throw NSError(
                domain: "ClashBar.ConfigImport",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Remote config response is empty"])
        }

        guard self.validateClashConfigData(data) else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary data>"
            let message = """
            Remote config is not a valid Clash configuration (missing proxy keys). \
            Content preview: \(preview)
            """
            throw NSError(
                domain: "ClashBar.ConfigImport",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: message])
        }

        try data.write(to: targetURL, options: .atomic)
    }

    private func validateClashConfigData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains("proxies:") || text.contains("proxy-groups:") || text.contains("proxy-providers:")
    }

    func normalizedConfigFileName(_ fileName: String, fallback: String? = nil) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? (fallback ?? "") : trimmed
        let candidate = URL(fileURLWithPath: baseName).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else { return nil }

        let ext = (candidate as NSString).pathExtension.lowercased()
        if ext.isEmpty {
            return "\(candidate).yaml"
        }
        guard ext == "yaml" || ext == "yml" else { return nil }
        return candidate
    }

    func inferredRemoteConfigFileName(from remoteURL: URL) -> String {
        let rawName = remoteURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return "remote-config.yaml" }

        let ext = (rawName as NSString).pathExtension.lowercased()
        if ext == "yaml" || ext == "yml" {
            return rawName
        }
        if ext.isEmpty {
            return "\(rawName).yaml"
        }

        let stem = (rawName as NSString).deletingPathExtension
        let base = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "remote-config.yaml" : "\(base).yaml"
    }

    func isSupportedRemoteConfigURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func downloadRemoteConfigData(from remoteURL: URL, userAgent: String? = nil) async throws -> Data {
        let session = URLSessionFactory.makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: remoteURL)
        if let userAgent {
            let trimmed = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                request.setValue(trimmed, forHTTPHeaderField: "User-Agent")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.statusCode(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }

        if data.count > self.maxRemoteConfigBytes {
            throw NSError(
                domain: "ClashBar.ConfigImport",
                code: 413,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Remote config exceeds size limit (\(self.maxRemoteConfigBytes) bytes)",
                ])
        }

        return data
    }

    func isValidFileName(_ fileName: String) -> Bool {
        self.normalizedConfigFileName(fileName, fallback: nil) == fileName
    }

    private func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = self.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        self.defaults.set(data, forKey: key)
    }

    isolated deinit {
        self.automaticUpdateTask?.cancel()
        self.menuRefreshTask?.cancel()
    }
}
