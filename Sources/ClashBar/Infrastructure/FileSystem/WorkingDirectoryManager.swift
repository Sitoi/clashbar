import Foundation

struct WorkingDirectoryManager {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    var rootDirectoryURL: URL {
        self.homeDirectory.appendingPathComponent("Library/Application Support/clashbar", isDirectory: true)
    }

    var configDirectoryURL: URL {
        self.rootDirectoryURL.appendingPathComponent("config", isDirectory: true)
    }

    var logsDirectoryURL: URL {
        self.rootDirectoryURL.appendingPathComponent("logs", isDirectory: true)
    }

    var coreDirectoryURL: URL {
        self.rootDirectoryURL.appendingPathComponent("core", isDirectory: true)
    }

    var managedMihomoBinaryURL: URL {
        self.coreDirectoryURL.appendingPathComponent("mihomo", isDirectory: false)
    }

    var iconDirectoryURL: URL {
        self.rootDirectoryURL.appendingPathComponent("icons", isDirectory: true)
    }

    func bootstrapDirectories(fileManager: FileManager = .default) throws {
        try self.createDirectoryIfNeeded(self.rootDirectoryURL, fileManager: fileManager)
        try self.createDirectoryIfNeeded(self.configDirectoryURL, fileManager: fileManager)
        try self.createDirectoryIfNeeded(self.logsDirectoryURL, fileManager: fileManager)
        try self.createDirectoryIfNeeded(self.coreDirectoryURL, fileManager: fileManager)
        try self.createDirectoryIfNeeded(self.iconDirectoryURL, fileManager: fileManager)
    }

    func normalizeAndValidateWithinRoot(_ url: URL, mustBeDirectory: Bool? = nil) throws -> URL {
        let standardized = url.standardizedFileURL
        let root = self.rootDirectoryURL.standardizedFileURL
        guard self.isDescendantOrEqual(standardized, parent: root) else {
            throw NSError(
                domain: "ClashBar.PathSecurity",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Path escapes ClashBar working directory: \(standardized.path)"])
        }

        if let mustBeDirectory {
            let resolved = standardized.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory != mustBeDirectory {
                throw NSError(
                    domain: "ClashBar.PathSecurity",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: mustBeDirectory
                        ? "Expected directory path: \(standardized.path)"
                        : "Expected file path: \(standardized.path)"])
            }
        }

        return standardized
    }

    private func createDirectoryIfNeeded(_ url: URL, fileManager: FileManager) throws {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw NSError(
                    domain: "ClashBar.PathSecurity",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Expected directory but found file: \(url.path)"])
            }
            return
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func isDescendantOrEqual(_ child: URL, parent: URL) -> Bool {
        let childComponents = child.pathComponents
        let parentComponents = parent.pathComponents

        guard parentComponents.count <= childComponents.count else { return false }
        return zip(parentComponents, childComponents).allSatisfy { $0 == $1 }
    }
}
