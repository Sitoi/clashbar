import Foundation

@MainActor
final class ConfigDirectoryManager {
    private let fm = FileManager.default
    private let workingDirectoryManager: WorkingDirectoryManager

    private(set) var configDirectory: URL?
    private(set) var availableConfigs: [URL] = []
    private(set) var selectedConfig: URL?

    init(workingDirectoryManager: WorkingDirectoryManager = WorkingDirectoryManager()) {
        self.workingDirectoryManager = workingDirectoryManager
    }

    func chooseConfigDirectory() -> URL? {
        do {
            try self.workingDirectoryManager.bootstrapDirectories()
            let target = try workingDirectoryManager.normalizeAndValidateWithinRoot(
                self.workingDirectoryManager.configDirectoryURL,
                mustBeDirectory: true)
            self.configDirectory = target
            self.reloadConfigs()
            return target
        } catch {
            return nil
        }
    }

    func setConfigDirectory(_ url: URL) {
        guard let safeURL = try? workingDirectoryManager.normalizeAndValidateWithinRoot(url, mustBeDirectory: true),
              safeURL == workingDirectoryManager.configDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        else {
            return
        }
        self.configDirectory = safeURL
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
    }

    @discardableResult
    func reloadConfigs() -> [URL] {
        guard let configDirectory else {
            self.availableConfigs = []
            selectedConfig = nil
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        let children = (try? self.fm.contentsOfDirectory(
            at: configDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])) ?? []
        var files: [URL] = []
        for fileURL in children {
            let isRegularFile = (try? fileURL.resourceValues(forKeys: Set(keys)).isRegularFile) ?? false
            guard isRegularFile else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "yaml" || ext == "yml" else { continue }
            files.append(fileURL)
        }

        files.sort { $0.lastPathComponent < $1.lastPathComponent }
        self.availableConfigs = files

        if let selectedConfig, files.contains(selectedConfig) {
            return files
        }
        selectedConfig = files.first
        return files
    }
}
