import AppKit

enum BrandIcon {
    private static let resourceExtension = "png"
    private static let resourceSubdirectory = "Brand"

    static let image: NSImage? = loadImage(name: "logo")
    static let runImage: NSImage? = loadImage(name: "icon-run")
    static let sleepImage: NSImage? = loadImage(name: "icon-sleep")

    private static func loadImage(name: String) -> NSImage? {
        for bundle in AppResourceBundleLocator.candidateBundles() {
            if let url = bundle.url(
                forResource: name,
                withExtension: resourceExtension,
                subdirectory: resourceSubdirectory), let image = NSImage(contentsOf: url)
            {
                return image
            }

            if let url = bundle.url(forResource: name, withExtension: resourceExtension),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }
        return nil
    }
}
