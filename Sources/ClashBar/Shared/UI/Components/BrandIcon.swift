import AppKit

@MainActor
enum BrandIcon {
    private static let logoRelativePaths = [
        "Assets.xcassets/BrandLogo.imageset/logo.png",
        "Resources/Assets.xcassets/BrandLogo.imageset/logo.png",
    ]
    private static let runRelativePaths = [
        "Assets.xcassets/BrandRun.imageset/icon-run.png",
        "Resources/Assets.xcassets/BrandRun.imageset/icon-run.png",
    ]
    private static let sleepRelativePaths = [
        "Assets.xcassets/BrandSleep.imageset/icon-sleep.png",
        "Resources/Assets.xcassets/BrandSleep.imageset/icon-sleep.png",
    ]
    private static let tunRelativePaths = [
        "Assets.xcassets/BrandTun.imageset/icon-tun.png",
        "Resources/Assets.xcassets/BrandTun.imageset/icon-tun.png",
    ]

    static let image: NSImage? = loadImage(relativePaths: logoRelativePaths)
    static let runImage: NSImage? = loadImage(relativePaths: runRelativePaths)
    static let sleepImage: NSImage? = loadImage(relativePaths: sleepRelativePaths)
    static let tunImage: NSImage? = loadImage(relativePaths: tunRelativePaths)

    private static func loadImage(relativePaths: [String]) -> NSImage? {
        for bundle in AppResourceBundleLocator.candidateBundles() {
            for relativePath in relativePaths {
                let url = bundle.bundleURL.appendingPathComponent(relativePath, isDirectory: false)
                if let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }
        return nil
    }
}
