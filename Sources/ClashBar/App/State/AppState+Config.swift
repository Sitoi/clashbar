import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppState {
    func seedBundledConfigIfNeeded() {
        let fileManager = FileManager.default
        let targetURL = workingDirectoryManager.configDirectoryURL
            .appendingPathComponent("ClashBar.yaml", isDirectory: false)

        if fileManager.fileExists(atPath: targetURL.path) {
            return
        }

        guard let bundledConfigURL = bundledDefaultConfigURL(fileManager: fileManager) else {
            return
        }

        do {
            let data = try Data(contentsOf: bundledConfigURL)
            try writeConfigData(data, to: targetURL)
        } catch {
            appendLog(
                level: "error",
                message: tr("log.config.import_local.failed", "ClashBar.yaml", error.localizedDescription))
        }
    }

    private func bundledDefaultConfigURL(fileManager: FileManager = .default) -> URL? {
        let candidateRelativePaths = [
            "ConfigTemplates/ClashBar.yaml",
            "Resources/ConfigTemplates/ClashBar.yaml",
            "ClashBar.yaml",
        ]

        for root in AppResourceBundleLocator.candidateResourceRoots() {
            for relativePath in candidateRelativePaths {
                let candidate = root.appendingPathComponent(relativePath, isDirectory: false)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    func selectConfig() async {
        let previousSelectedURL = configManager.selectedConfig
        let previousSelectedPath = configManager.selectedConfig?.path
        guard configManager.chooseConfigDirectory() != nil else { return }

        let nextSelectedURL = configManager.selectedConfig
        let previousCanonicalPath = previousSelectedURL?.standardizedFileURL.resolvingSymlinksInPath().path
        let nextCanonicalPath = nextSelectedURL?.standardizedFileURL.resolvingSymlinksInPath().path

        if processManager.isRunning,
           let nextSelectedURL,
           previousCanonicalPath != nextCanonicalPath,
           !self.validateConfigBeforeCoreLaunch(configPath: nextSelectedURL.path)
        {
            if let previousSelectedURL {
                configManager.selectConfig(previousSelectedURL)
            }
            _ = self.syncSelectedConfigSelection(configManager.selectedConfig)
            syncConfigDisplayState()
            return
        }

        let nextSelectedPath = self.syncSelectedConfigSelection(configManager.selectedConfig)
        syncConfigDisplayState()

        appendLog(level: "info", message: tr("log.config.loaded_count", configManager.availableConfigs.count))
        await restartCoreIfNeededForConfigSwitch(previousPath: previousSelectedPath, nextPath: nextSelectedPath)
    }

    func selectConfigFile(named fileName: String) async {
        let previousSelectedURL = configManager.selectedConfig
        let previousSelectedPath = configManager.selectedConfig?.path
        guard let matched = configManager.availableConfigs.first(where: { $0.lastPathComponent == fileName }) else {
            appendLog(level: "error", message: tr("log.config.not_found", fileName))
            return
        }

        let previousCanonicalPath = previousSelectedURL?.standardizedFileURL.resolvingSymlinksInPath().path
        let targetCanonicalPath = matched.standardizedFileURL.resolvingSymlinksInPath().path

        if processManager.isRunning,
           previousCanonicalPath != targetCanonicalPath,
           !self.validateConfigBeforeCoreLaunch(configPath: matched.path)
        {
            if let previousSelectedURL {
                configManager.selectConfig(previousSelectedURL)
            }
            _ = self.syncSelectedConfigSelection(configManager.selectedConfig)
            syncConfigDisplayState()
            return
        }

        configManager.selectConfig(matched)
        let nextSelectedPath = self.syncSelectedConfigSelection(matched)
        syncConfigDisplayState()
        appendLog(level: "info", message: tr("log.config.selected", fileName))
        await restartCoreIfNeededForConfigSwitch(previousPath: previousSelectedPath, nextPath: nextSelectedPath)
    }

    func importLocalConfigFile() {
        guard let configDirectory = ensureConfigDirectoryAvailable() else { return }

        self.prepareModalWindowPresentation()
        let panel = NSOpenPanel()
        self.configureModalWindow(panel)
        panel.title = tr("ui.quick.import_local_config")
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
        guard let fileName = normalizedConfigFileName(sourceURL.lastPathComponent) else {
            appendLog(level: "error", message: tr("log.config.import.invalid_filename", sourceURL.lastPathComponent))
            return
        }

        let targetURL = configDirectory.appendingPathComponent(fileName, isDirectory: false)
        let isOverwrite = FileManager.default.fileExists(atPath: targetURL.path)
        guard !isOverwrite || self.confirmOverwriteConfig(named: fileName) else {
            appendLog(level: "info", message: tr("log.config.import.cancelled", fileName))
            return
        }

        do {
            let data = try Data(contentsOf: sourceURL)
            try writeConfigData(data, to: targetURL)

            self.updateRemoteConfigSource(for: fileName, urlString: nil)
            appendLog(level: "info", message: tr("log.config.import_local.success", fileName))

            if isOverwrite, self.shouldAutoReloadCurrentConfig(updatedFileNames: [fileName]) {
                Task { await self.reloadConfig() }
            }
        } catch {
            appendLog(
                level: "error",
                message: tr("log.config.import_local.failed", fileName, error.localizedDescription))
        }
    }

    func importRemoteConfigFile() async {
        guard let configDirectory = ensureConfigDirectoryAvailable() else { return }
        guard let input = promptRemoteConfigImportInput() else { return }

        let urlText = input.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remoteURL = URL(string: urlText), isSupportedRemoteConfigURL(remoteURL) else {
            let message = tr("log.config.remote.invalid_url", urlText)
            appendLog(level: "error", message: message)
            self.presentRemoteConfigImportResultAlert(success: false, message: message)
            return
        }

        let fallbackName = self.inferredRemoteConfigFileName(from: remoteURL)
        guard let fileName = normalizedConfigFileName(input.fileName, fallback: fallbackName) else {
            let message = tr("log.config.import.invalid_filename", input.fileName)
            appendLog(level: "error", message: message)
            self.presentRemoteConfigImportResultAlert(success: false, message: message)
            return
        }

        let targetURL = configDirectory.appendingPathComponent(fileName, isDirectory: false)
        let isOverwrite = FileManager.default.fileExists(atPath: targetURL.path)
        guard !isOverwrite || self.confirmOverwriteConfig(named: fileName) else {
            appendLog(level: "info", message: tr("log.config.import.cancelled", fileName))
            return
        }

        do {
            let data = try await downloadRemoteConfigData(from: remoteURL)
            try writeConfigData(data, to: targetURL)

            self.updateRemoteConfigSource(for: fileName, urlString: remoteURL.absoluteString)
            let message = tr("log.config.import_remote.success", fileName)
            appendLog(level: "info", message: message)

            if isOverwrite, self.shouldAutoReloadCurrentConfig(updatedFileNames: [fileName]) {
                await self.reloadConfig()
            }

            self.presentRemoteConfigImportResultAlert(success: true, message: message)
        } catch {
            let message = tr("log.config.import_remote.failed", fileName, error.localizedDescription)
            appendLog(level: "error", message: message)
            self.presentRemoteConfigImportResultAlert(success: false, message: message)
        }
    }

    func updateAllRemoteConfigFiles() async {
        guard let configDirectory = ensureConfigDirectoryAvailable() else { return }
        pruneRemoteConfigSourcesIfNeeded()

        let sources = remoteConfigSources
        guard !sources.isEmpty else {
            appendLog(level: "info", message: tr("log.config.remote.no_sources"))
            return
        }

        var updatedFileNames: Set<String> = []
        var failedCount = 0

        for fileName in sources.keys.sorted() {
            guard let urlString = sources[fileName],
                  let remoteURL = URL(string: urlString),
                  isSupportedRemoteConfigURL(remoteURL)
            else {
                failedCount += 1
                appendLog(
                    level: "error",
                    message: tr(
                        "log.config.remote.update_item_failed",
                        fileName,
                        tr("log.config.remote.invalid_url", sources[fileName] ?? fileName)))
                continue
            }

            let targetURL = configDirectory.appendingPathComponent(fileName, isDirectory: false)
            do {
                let data = try await downloadRemoteConfigData(from: remoteURL)
                try writeConfigData(data, to: targetURL)
                updatedFileNames.insert(fileName)
            } catch {
                failedCount += 1
                appendLog(
                    level: "error",
                    message: tr("log.config.remote.update_item_failed", fileName, error.localizedDescription))
            }
        }

        self.refreshConfigStateAfterMutation()
        appendLog(level: "info", message: tr("log.config.remote.update_summary", updatedFileNames.count, failedCount))

        if self.shouldAutoReloadCurrentConfig(updatedFileNames: updatedFileNames) {
            await self.reloadConfig()
        }
    }

    func showSelectedConfigInFinder() {
        guard let configDirectory = ensureConfigDirectoryAvailable() else { return }
        if let selected = configManager.selectedConfig, FileManager.default.fileExists(atPath: selected.path) {
            NSWorkspace.shared.activateFileViewerSelecting([selected])
            return
        }

        if !NSWorkspace.shared.open(configDirectory) {
            appendLog(level: "error", message: tr("log.config.show_in_finder.failed", configDirectory.path))
        }
    }

    func showCoreDirectoryInFinder() {
        do {
            try workingDirectoryManager.bootstrapDirectories()
            let coreDirectory = try workingDirectoryManager.normalizeAndValidateWithinRoot(
                workingDirectoryManager.coreDirectoryURL,
                mustBeDirectory: true)
            if !NSWorkspace.shared.open(coreDirectory) {
                appendLog(level: "error", message: tr("log.core.show_in_finder.failed", coreDirectory.path))
            }
        } catch {
            appendLog(
                level: "error",
                message: tr("log.core.show_in_finder.failed", workingDirectoryManager.coreDirectoryURL.path))
        }
    }

    func reloadConfigFileList() {
        guard self.ensureConfigDirectoryAvailable() != nil else { return }
        self.refreshConfigStateAfterMutation()
        appendLog(level: "info", message: tr("log.config.loaded_count", configManager.availableConfigs.count))
    }

    func reloadConfig() async {
        await runNoResponseAction(tr("log.action_name.reload_config")) {
            try await self.clientOrThrow().requestNoResponse(.putConfigs(force: false))
        }
    }

    func ensureConfigDirectoryAvailable() -> URL? {
        if let configDirectory = configManager.configDirectory {
            return configDirectory
        }

        do {
            try workingDirectoryManager.bootstrapDirectories()
            configManager.setConfigDirectory(workingDirectoryManager.configDirectoryURL)
            self.refreshConfigStateAfterMutation()
            return configManager.configDirectory
        } catch {
            appendLog(level: "error", message: tr("log.working_dir_init_failed", error.localizedDescription))
            return nil
        }
    }

    private func refreshConfigStateAfterMutation() {
        _ = configManager.reloadConfigs()
        if self.syncSelectedConfigSelection(configManager.selectedConfig) == nil {
            selectedConfigName = "-"
            defaults.removeObject(forKey: selectedConfigKey)
        }
        syncConfigDisplayState()
    }

    @discardableResult
    func syncSelectedConfigSelection(_ selected: URL?) -> String? {
        guard let selected else {
            return nil
        }
        // DRY: keep selected config state/defaults updates in one place.
        selectedConfigName = selected.lastPathComponent
        defaults.set(selected.lastPathComponent, forKey: selectedConfigKey)
        return selected.path
    }

    private func shouldAutoReloadCurrentConfig(updatedFileNames: Set<String>) -> Bool {
        guard !updatedFileNames.isEmpty else { return false }
        guard isRuntimeRunning else { return false }
        return updatedFileNames.contains(selectedConfigName)
    }

    private func writeConfigData(_ data: Data, to targetURL: URL) throws {
        try configImportService.writeConfigData(data, to: targetURL)
    }

    private func confirmOverwriteConfig(named fileName: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("app.config.import.overwrite.title", fileName)
        alert.informativeText = tr("app.config.import.overwrite.message")
        alert.addButton(withTitle: tr("ui.action.overwrite"))
        alert.addButton(withTitle: tr("ui.action.cancel"))
        self.prepareModalWindowPresentation()
        self.configureModalWindow(alert.window)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentRemoteConfigImportResultAlert(success: Bool, message: String) {
        let alert = NSAlert()
        alert.alertStyle = success ? .informational : .warning
        alert.messageText = success
            ? tr("app.config.remote_import.alert.success.title")
            : tr("app.config.remote_import.alert.failure.title")
        alert.informativeText = message
        alert.addButton(withTitle: tr("ui.action.ok"))
        self.prepareModalWindowPresentation()
        self.configureModalWindow(alert.window)
        alert.runModal()
    }

    private struct RemoteConfigImportInput {
        let urlString: String
        let fileName: String
    }

    private func promptRemoteConfigImportInput() -> RemoteConfigImportInput? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = tr("ui.quick.import_remote_config")
        alert.informativeText = tr("app.config.remote_import.prompt")
        alert.addButton(withTitle: tr("ui.action.import"))
        alert.addButton(withTitle: tr("ui.action.cancel"))

        // Use fixed frames in accessory view to avoid NSAlert auto-layout overlap in compact windows.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 96))

        let urlLabel = NSTextField(labelWithString: tr("ui.quick.remote.url_label"))
        urlLabel.font = .systemFont(ofSize: 12, weight: .medium)
        urlLabel.frame = NSRect(x: 0, y: 76, width: 340, height: 16)

        let urlField = NSTextField(frame: NSRect(x: 0, y: 50, width: 340, height: 24))
        urlField.placeholderString = tr("ui.quick.remote.url_placeholder")

        let fileLabel = NSTextField(labelWithString: tr("ui.quick.remote.filename_label"))
        fileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fileLabel.frame = NSRect(x: 0, y: 30, width: 340, height: 16)

        let fileField = NSTextField(frame: NSRect(x: 0, y: 4, width: 340, height: 24))
        fileField.placeholderString = tr("ui.quick.remote.filename_placeholder")

        container.addSubview(urlLabel)
        container.addSubview(urlField)
        container.addSubview(fileLabel)
        container.addSubview(fileField)
        alert.accessoryView = container

        self.prepareModalWindowPresentation()
        self.configureModalWindow(alert.window)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return RemoteConfigImportInput(
            urlString: urlField.stringValue,
            fileName: fileField.stringValue)
    }

    func prepareModalWindowPresentation() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func configureModalWindow(_ window: NSWindow) {
        window.level = .statusBar
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    func normalizedConfigFileName(_ fileName: String, fallback: String? = nil) -> String? {
        configImportService.normalizedConfigFileName(fileName, fallback: fallback)
    }

    private func inferredRemoteConfigFileName(from remoteURL: URL) -> String {
        configImportService.inferredRemoteConfigFileName(from: remoteURL)
    }

    func isSupportedRemoteConfigURL(_ url: URL) -> Bool {
        configImportService.isSupportedRemoteConfigURL(url)
    }

    private func downloadRemoteConfigData(from remoteURL: URL) async throws -> Data {
        try await configImportService.downloadRemoteConfigData(from: remoteURL)
    }

    private func updateRemoteConfigSource(for fileName: String, urlString: String?) {
        if let urlString {
            remoteConfigSources[fileName] = urlString
        } else {
            remoteConfigSources.removeValue(forKey: fileName)
        }
        persistRemoteConfigSources()
        self.refreshConfigStateAfterMutation()
    }
}
