import AppKit

enum BrandIcon {
    private static let resourceName = "icon"
    private static let resourceExtension = "png"
    private static let resourceSubdirectory = "Brand"

    static let image: NSImage? = {
        for bundle in AppResourceBundleLocator.candidateBundles() {
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: resourceExtension,
                subdirectory: resourceSubdirectory), let image = NSImage(contentsOf: url)
            {
                return image
            }

            if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }
        return nil
    }()
}
