import Foundation

enum AppResourceBundleLocator {
    private static let moduleBundleName = "ClashBar_ClashBar.bundle"

    static func moduleBundle() -> Bundle? {
        for url in self.candidateModuleBundleURLs() {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        if let module = moduleBundle() {
            bundles.append(module)
        }
        bundles.append(Bundle.main)
        return bundles
    }

    static func candidateResourceRoots() -> [URL] {
        var roots: [URL] = []
        if let module = moduleBundle(), let moduleRoot = module.resourceURL {
            roots.append(moduleRoot)
        }
        if let mainRoot = Bundle.main.resourceURL {
            roots.append(mainRoot)
        }
        return self.deduplicated(roots)
    }

    private static func candidateModuleBundleURLs() -> [URL] {
        var urls: [URL] = []

        let appBundleURL = Bundle.main.bundleURL
        urls.append(appBundleURL.appendingPathComponent(self.moduleBundleName, isDirectory: true))

        if let appResourcesURL = Bundle.main.resourceURL {
            urls.append(appResourcesURL.appendingPathComponent(self.moduleBundleName, isDirectory: true))
            urls.append(
                appResourcesURL
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(self.moduleBundleName, isDirectory: true))
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
        let executableDirectoryURL = executableURL.deletingLastPathComponent()
        urls.append(executableDirectoryURL.appendingPathComponent(self.moduleBundleName, isDirectory: true))

        return self.deduplicated(urls)
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }
}
